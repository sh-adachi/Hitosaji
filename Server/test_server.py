"""Offline unit + real-loopback HTTP tests. No OpenAI credentials/network needed."""
import base64
import contextlib
import copy
import http.client
import io
import json
import os
import socket
import threading
import time
import unittest
from unittest.mock import patch

import server as app


TOKEN = "local-test-token-" + "a" * 32
CONFIG = app.Config(api_key="test-key-never-sent", token=TOKEN, port=0)


def jpeg(width=1, height=1, progressive=False):
    # Structurally complete marker fixture: no external image libraries required.
    # Upstream is mocked; this fixture doesn't claim to test entropy decoding.
    sof = bytes([8]) + height.to_bytes(2, "big") + width.to_bytes(2, "big") + b"\x01\x01\x11\x00"
    sos = b"\x01\x01\x00\x00\x3f\x00"
    marker = b"\xc2" if progressive else b"\xc0"
    return b"\xff\xd8\xff" + marker + (len(sof) + 2).to_bytes(2, "big") + sof + b"\xff\xda" + (len(sos) + 2).to_bytes(2, "big") + sos + b"\x01\xff\x00\x02\xff\xd9"


def request_body(**changes):
    body = {"imageBase64": base64.b64encode(jpeg()).decode(), "mimeType": "image/jpeg", "hint": "ごはんは小盛り"}
    body.update(changes)
    return json.dumps(body, ensure_ascii=False).encode("utf-8")


def result():
    return {"items": [{"name": "ごはん", "serving": "茶碗1杯・約150g", "nutrition": {
        "energy": 234, "protein": 3.8, "fat": 0.5, "carbs": 55.7, "fiber": None, "salt": None,
    }, "confidence": "medium", "reason": "写真から茶碗1杯と推定。正確な重量は不明です。"}], "note": "写真からの概算です。保存前に量・栄養値を確認してください。"}


def response_for(value=None):
    return {"status": "completed", "output": [{"type": "message", "role": "assistant", "content": [{
        "type": "output_text", "text": json.dumps(result() if value is None else value),
    }]}]}


@contextlib.contextmanager
def running_server(analyzer=None):
    server = app.AnalysisServer(CONFIG, analyzer or (lambda image, hint: result()))
    thread = threading.Thread(target=server.serve_forever, kwargs={"poll_interval": 0.01}, daemon=True)
    thread.start()
    try:
        yield server
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)


def post(server, body=None, headers=None, method="POST", path="/v1/meal-analysis"):
    connection = http.client.HTTPConnection("127.0.0.1", server.server_port, timeout=2)
    base = {"Authorization": "Bearer " + TOKEN, "Content-Type": "application/json"}
    if headers:
        base.update(headers)
    try:
        connection.request(method, path, body=request_body() if body is None else body, headers=base)
        response = connection.getresponse()
        return response.status, dict(response.getheaders()), json.loads(response.read())
    finally:
        connection.close()


class RequestValidationTests(unittest.TestCase):
    def assert_error(self, status, function, *args):
        with self.assertRaises(app.APIError) as caught:
            function(*args)
        self.assertEqual(caught.exception.status, status)
        return caught.exception

    def test_valid_jpeg_and_optional_hint(self):
        image, hint = app.parse_request(request_body())
        self.assertEqual(base64.b64decode(image), jpeg())
        self.assertEqual(hint, "ごはんは小盛り")
        obj = json.loads(request_body())
        del obj["hint"]
        self.assertEqual(app.parse_request(json.dumps(obj).encode())[1], "")
        app.validate_jpeg(jpeg(progressive=True))

    def test_bad_json_missing_extra_and_duplicate_keys(self):
        for raw in [b"{", b"null", b"[]", b"{}", b"{\"hint\":NaN}", b'{"a":1,"a":2}', b"\xff", b"[" * 2000, request_body(extra=1)]:
            with self.subTest(raw=raw[:20]):
                self.assert_error(400, app.parse_request, raw)

    def test_mime_base64_and_hint_type_validation(self):
        for changes in [{"mimeType": "image/png"}, {"imageBase64": 123}, {"imageBase64": "@@@"}, {"imageBase64": "日本語"}, {"hint": None}, {"hint": "a" * 501}, {"hint": "\x00"}, {"hint": "\ud800"}]:
            with self.subTest(changes=list(changes)):
                raw = json.dumps(dict(json.loads(request_body()), **changes)).encode()
                self.assert_error(400, app.parse_request, raw)

    def test_request_and_image_byte_limits(self):
        self.assert_error(413, app.parse_request, b" " * (app.MAX_BODY_BYTES + 1))
        self.assert_error(413, app.parse_request, request_body(imageBase64="A" * (4 * ((app.MAX_IMAGE_BYTES + 2) // 3) + 1)))
        encoded = base64.b64encode(b"x" * (app.MAX_IMAGE_BYTES + 1)).decode()
        self.assert_error(413, app.parse_request, request_body(imageBase64=encoded))

    def test_truncated_fake_and_malformed_jpeg(self):
        for image in [b"", b"PNG" * 20, b"\xff\xd8" + b"x" * 30 + b"\xff\xd9", jpeg()[:-1], jpeg() + b"trailing", jpeg().replace(b"\xff\xda\x00\x08", b"\xff\xda\x00\xff"), jpeg().replace(b"\xff\xc0", b"\xff\xc3")]:
            self.assert_error(400, app.validate_jpeg, image)

    def test_dimension_limits(self):
        for image in [jpeg(width=4097), jpeg(height=4097), jpeg(width=4096, height=4096)]:
            self.assert_error(413, app.validate_jpeg, image)
        app.validate_jpeg(jpeg(width=4000, height=4000))
        self.assert_error(400, app.validate_jpeg, jpeg(width=0))


class ResultValidationTests(unittest.TestCase):
    def test_result_and_null_nutrients_round_trip(self):
        self.assertEqual(app.parse_response(response_for()), result())
        data = result()
        data["items"][0]["nutrition"]["salt"] = 0
        self.assertEqual(app.validate_result(data), data)

    def test_nonfood_returns_empty_items_and_actionable_note(self):
        value = app.parse_response(response_for({"items": [], "note": ""}))
        self.assertEqual(value["items"], [])
        self.assertIn("食品を確認できません", value["note"])

    def test_nutrient_bounds_types_and_unknowns(self):
        for name, maximum in app.NUTRIENT_LIMITS.items():
            for bad in [True, "3", -1, maximum + 1, float("nan"), float("inf")]:
                data = result()
                data["items"][0]["nutrition"][name] = bad
                with self.subTest(name=name, value=bad), self.assertRaises(app.APIError):
                    app.validate_result(data)
            data = result()
            data["items"][0]["nutrition"][name] = maximum
            app.validate_result(data)
        for name in ["energy", "protein", "fat", "carbs"]:
            data = result()
            data["items"][0]["nutrition"][name] = None
            with self.assertRaises(app.APIError):
                app.validate_result(data)

    def test_model_string_enum_schema_and_item_bounds(self):
        bad_results = [{}, [], {"items": [], "note": "", "extra": 1}]
        for field, value in [("name", " "), ("name", "n" * 201), ("serving", "s" * 201), ("reason", "r" * 501), ("confidence", "certain"), ("name", "\ud800"), ("serving", "\x00")]:
            data = result()
            data["items"][0][field] = value
            bad_results.append(data)
        data = result()
        data["items"] *= 13
        bad_results.append(data)
        data = result()
        data["note"] = "n" * 1001
        bad_results.append(data)
        data = result()
        del data["items"][0]["nutrition"]["salt"]
        bad_results.append(data)
        for value in bad_results:
            with self.assertRaises(app.APIError):
                app.validate_result(value)

    def test_refusal_incomplete_bad_status_and_no_output(self):
        refusal = {"status": "completed", "output": [{"type": "message", "content": [{"type": "refusal", "refusal": "private upstream refusal"}]}]}
        with self.assertRaises(app.APIError) as caught:
            app.parse_response(refusal)
        self.assertEqual(caught.exception.code, "analysis_refused")
        self.assertNotIn("private", str(caught.exception.body()))
        with self.assertRaises(app.APIError) as caught:
            app.parse_response({"status": "incomplete", "incomplete_details": {"reason": "max_output_tokens"}})
        self.assertEqual(caught.exception.code, "analysis_incomplete")
        for obj in [{"status": "failed"}, {"status": "completed", "output": []}, {"status": "completed", "output": None}, response_for({"broken": 2})]:
            with self.assertRaises(app.APIError):
                app.parse_response(obj)

    def test_malformed_model_json_and_duplicate_keys(self):
        for text in ["not JSON", '{"items":[],"note":"","note":"duplicated"}', "[" * 2000]:
            obj = response_for()
            obj["output"][0]["content"][0]["text"] = text
            with self.assertRaises(app.APIError):
                app.parse_response(obj)


class FakeResponse:
    def __init__(self, raw=None, status=200):
        self.status = status
        self.stream = io.BytesIO(json.dumps(response_for()).encode() if raw is None else raw)

    def read1(self, size):
        return self.stream.read(size)


class FakeConnection:
    def __init__(self, response=None, failure=None):
        self.response = response or FakeResponse()
        self.failure = failure
        self.sock = None
        self.request_args = None
        self.closed = False

    def request(self, *args, **kwargs):
        self.request_args = (args, kwargs)
        if self.failure:
            raise self.failure

    def getresponse(self):
        return self.response

    def close(self):
        self.closed = True


class UpstreamTests(unittest.TestCase):
    def call(self, connection):
        with patch.object(app.http.client, "HTTPSConnection", return_value=connection) as constructor:
            value = app.upstream_request(CONFIG, "IMAGE", "hint")
        self.assertEqual(constructor.call_args.args[0], "api.openai.com")
        return value

    def test_fixed_endpoint_schema_store_false_and_no_secret_in_payload(self):
        connection = FakeConnection()
        self.assertEqual(self.call(connection), result())
        args, kwargs = connection.request_args
        self.assertEqual(args, ("POST", "/v1/responses"))
        payload = json.loads(kwargs["body"])
        self.assertFalse(payload["store"])
        self.assertEqual(payload["model"], "gpt-4.1-mini")
        self.assertEqual(payload["max_output_tokens"], 5000)
        self.assertTrue(payload["text"]["format"]["strict"])
        self.assertEqual(payload["text"]["format"]["schema"], app.RESULT_SCHEMA)
        self.assertEqual(payload["input"][0]["content"][1]["image_url"], "data:image/jpeg;base64,IMAGE")
        self.assertNotIn(CONFIG.api_key, str(payload))
        self.assertTrue(connection.closed)

    def test_upstream_error_and_redirect_never_exposes_body_or_retries(self):
        for status in [301, 401, 403, 429, 500, 503]:
            connection = FakeConnection(FakeResponse(b"SECRET upstream internals", status))
            with self.assertRaises(app.APIError) as caught:
                self.call(connection)
            self.assertEqual(caught.exception.status, 503 if status == 429 else 502)
            self.assertNotIn("SECRET", str(caught.exception.body()))
            self.assertTrue(connection.closed)

    def test_timeouts_network_errors_malformed_oversized_response(self):
        for failure, expected in [(socket.timeout("secret"), 504), (OSError("secret"), 502), (http.client.RemoteDisconnected("secret"), 502)]:
            with self.assertRaises(app.APIError) as caught:
                self.call(FakeConnection(failure=failure))
            self.assertEqual(caught.exception.status, expected)
            self.assertNotIn("secret", str(caught.exception.body()))
        for raw in [b"not JSON", b"\xff", b"a" * (app.MAX_UPSTREAM_BYTES + 1), b"[" * 2000]:
            with self.assertRaises(app.APIError) as caught:
                self.call(FakeConnection(FakeResponse(raw)))
            self.assertEqual(caught.exception.status, 502)


class ConfigurationAndRateTests(unittest.TestCase):
    def test_required_secrets_and_bounded_env_settings(self):
        with patch.dict(os.environ, {}, clear=True), self.assertRaises(ValueError):
            app.Config.from_env()
        env = {"OPENAI_API_KEY": "test", "HITOSAJI_ANALYSIS_TOKEN": TOKEN}
        with patch.dict(os.environ, env, clear=True):
            self.assertEqual(app.Config.from_env().host, "127.0.0.1")
        for change in [{"HITOSAJI_ANALYSIS_TOKEN": "short"}, {"HITOSAJI_ANALYSIS_TOKEN": "\n" * 32}, {"PORT": "0"}, {"PORT": "abc"}, {"OPENAI_API_KEY": "key\r\ninjected"}, {"OPENAI_MODEL": ""}]:
            with patch.dict(os.environ, dict(env, **change), clear=True), self.assertRaises(ValueError):
                app.Config.from_env()

    def test_rate_limit_window_and_bounded_memory(self):
        now = [10.0]
        limiter = app.RateLimiter(2, lambda: now[0])
        self.assertTrue(limiter.allow())
        self.assertTrue(limiter.allow())
        self.assertFalse(limiter.allow())
        self.assertEqual(len(limiter.times), 2)
        now[0] = 70.0
        self.assertTrue(limiter.allow())
        self.assertEqual(len(limiter.times), 1)


class HTTPTests(unittest.TestCase):
    def test_success_real_http_and_sensitive_data_not_logged(self):
        calls = []
        def analyze(image, hint):
            calls.append((image, hint))
            return result()
        with contextlib.redirect_stderr(io.StringIO()) as errors, running_server(analyze) as server:
            status, headers, body = post(server)
        self.assertEqual(status, 200)
        self.assertEqual(body, result())
        self.assertEqual(headers["Cache-Control"], "no-store")
        self.assertEqual(headers["Connection"], "close")
        self.assertEqual(len(calls), 1)
        self.assertEqual(calls[0][1], "ごはんは小盛り")
        self.assertEqual(errors.getvalue(), "")

    def test_auth_before_body_validation_and_analyzer(self):
        calls = []
        with running_server(lambda *args: calls.append(args)) as server:
            for token in ["", "Bearer wrong", "Basic " + TOKEN, "Bearer " + TOKEN + "x"]:
                status, headers, body = post(server, b"bad JSON", {"Authorization": token})
                self.assertEqual(status, 401)
                self.assertEqual(body["error"]["code"], "unauthorized")
                self.assertIn("WWW-Authenticate", headers)
        self.assertEqual(calls, [])

    def test_invalid_request_routing_and_content_headers(self):
        with running_server() as server:
            for kwargs, status in [({"path": "/other"}, 404), ({"method": "GET"}, 405), ({"headers": {"Content-Type": "image/jpeg"}}, 415), ({"body": b"{}"}, 400), ({"headers": {"Content-Encoding": "gzip"}}, 400), ({"headers": {"Transfer-Encoding": "chunked"}}, 400), ({"headers": {"Content-Length": str(app.MAX_BODY_BYTES + 1)}, "body": b""}, 413)]:
                with self.subTest(kwargs=kwargs):
                    response, _, body = post(server, **kwargs)
                    self.assertEqual(response, status)
                    self.assertEqual(set(body), {"error"})

    def test_rate_limit_and_concurrency(self):
        with running_server() as server:
            server.limiter = app.RateLimiter(1)
            self.assertEqual(post(server)[0], 200)
            status, headers, _ = post(server)
            self.assertEqual(status, 429)
            self.assertEqual(headers["Retry-After"], "60")
        with running_server() as server:
            for _ in range(app.UPSTREAM_WORKERS):
                server.analysis_slots.acquire()
            try:
                self.assertEqual(post(server)[0], 503)
            finally:
                for _ in range(app.UPSTREAM_WORKERS):
                    server.analysis_slots.release()

    def test_model_revalidated_and_internal_errors_sanitized(self):
        def raises(*args):
            raise ValueError("sensitive upstream content")
        with running_server(raises) as server:
            status, _, body = post(server)
            self.assertEqual(status, 500)
            self.assertNotIn("sensitive", str(body))
        with running_server(lambda *args: {"items": [], "note": "", "bad": "value"}) as server:
            self.assertEqual(post(server)[0], 502)
        with running_server(lambda *args: {"items": [], "note": ""}) as server:
            status, _, body = post(server)
            self.assertEqual(status, 200)
            self.assertEqual(body["items"], [])

    def test_failed_analysis_releases_capacity(self):
        count = [0]
        def analyze(*args):
            count[0] += 1
            if count[0] <= 3:
                raise app.APIError(504, "analysis_timeout", "時間内に終わりませんでした。")
            return result()
        with running_server(analyze) as server:
            for _ in range(3):
                self.assertEqual(post(server)[0], 504)
            self.assertEqual(post(server)[0], 200)

    def test_slow_request_has_absolute_deadline(self):
        with patch.object(app, "REQUEST_TIMEOUT", 0.15), running_server() as server:
            sock = socket.create_connection(("127.0.0.1", server.server_port), timeout=2)
            try:
                sock.sendall(b"POST /v1/meal-analysis HTTP/1.1\r\nHost: localhost\r\n")
                time.sleep(0.25)
                self.assertEqual(sock.recv(100), b"")
            finally:
                sock.close()


if __name__ == "__main__":
    unittest.main()
