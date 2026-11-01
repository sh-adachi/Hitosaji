import Foundation
import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import NutritionCore

// Every session has a unique host routed by a locked registry. No test can contact a real server.
private final class PhotoRequestStub: @unchecked Sendable {
    enum Reply: Sendable {
        case http(Int, Data)
        case nonHTTP(Data)
        case failure(URLError.Code)
        case waitForCancellation
    }

    struct CapturedRequest: Sendable {
        let url: URL?
        let method: String?
        let headers: [String: String]
        let cachePolicy: URLRequest.CachePolicy
        let body: Data
    }

    let reply: Reply
    let onStart: (@Sendable () -> Void)?
    let onStop: (@Sendable () -> Void)?
    private let lock = NSLock()
    private var captured: [CapturedRequest] = []

    init(reply: Reply, onStart: (@Sendable () -> Void)? = nil, onStop: (@Sendable () -> Void)? = nil) {
        self.reply = reply
        self.onStart = onStart
        self.onStop = onStop
    }

    var requests: [CapturedRequest] { lock.withLock { captured } }

    func record(_ request: URLRequest) {
        let item = CapturedRequest(url: request.url, method: request.httpMethod,
                                   headers: request.allHTTPHeaderFields ?? [:], cachePolicy: request.cachePolicy,
                                   body: Self.body(of: request))
        lock.withLock { captured.append(item) }
        onStart?()
    }

    private static func body(of request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var body = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while true {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { return body }
            body.append(contentsOf: buffer.prefix(count))
        }
    }
}

private final class PhotoStubRegistry: @unchecked Sendable {
    static let shared = PhotoStubRegistry()
    private let lock = NSLock()
    private var stubs: [String: PhotoRequestStub] = [:]

    func register(_ stub: PhotoRequestStub, host: String) { lock.withLock { stubs[host] = stub } }
    func stub(for host: String) -> PhotoRequestStub? { lock.withLock { stubs[host] } }
    func remove(host: String) { _ = lock.withLock { stubs.removeValue(forKey: host) } }
}

private final class PhotoStubURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let host = url.host, let stub = PhotoStubRegistry.shared.stub(for: host) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        stub.record(request)
        switch stub.reply {
        case .http(let status, let data):
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        case .nonHTTP(let data):
            let response = URLResponse(url: url, mimeType: "application/json", expectedContentLength: data.count, textEncodingName: "utf-8")
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        case .failure(let code):
            let error = URLError(code, userInfo: [NSLocalizedDescriptionKey: "PRIVATE_SERVER_DETAIL_do_not_display"])
            client?.urlProtocol(self, didFailWithError: error)
        case .waitForCancellation:
            break
        }
    }

    override func stopLoading() {
        guard let host = request.url?.host else { return }
        PhotoStubRegistry.shared.stub(for: host)?.onStop?()
    }
}

private struct PhotoTransportHarness: Sendable {
    let endpoint: URL
    let stub: PhotoRequestStub
    let session: URLSession
    let transport: PhotoAnalysisTransport

    init(reply: PhotoRequestStub.Reply, onStart: (@Sendable () -> Void)? = nil, onStop: (@Sendable () -> Void)? = nil) throws {
        let host = "test-\(UUID().uuidString.lowercased()).example.test"
        endpoint = try PhotoAnalysisEndpoint.validated("https://\(host)")
        stub = PhotoRequestStub(reply: reply, onStart: onStart, onStop: onStop)
        PhotoStubRegistry.shared.register(stub, host: host)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PhotoStubURLProtocol.self]
        configuration.urlCache = nil
        session = URLSession(configuration: configuration)
        transport = PhotoAnalysisTransport(session: session)
    }

    func close() {
        session.invalidateAndCancel()
        if let host = endpoint.host { PhotoStubRegistry.shared.remove(host: host) }
    }
}

// The test case has no shared mutable properties. Stub state is protected by locks.
final class PhotoAnalysisTransportTests: XCTestCase, @unchecked Sendable {
    private let jpeg = Data([0xff, 0xd8, 0x12, 0x34, 0xff, 0xd9])
    private let token = String(repeating: "a", count: 32)
    private let emptyResponse = Data("{\"items\":[],\"note\":\"食品を確認できませんでした。\"}".utf8)

    private func assertFailure(_ expected: PhotoServiceError, operation: () async throws -> PhotoAnalysisResult,
                               file: StaticString = #filePath, line: UInt = #line) async {
        do {
            _ = try await operation()
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? PhotoServiceError, expected, file: file, line: line)
            XCTAssertFalse(error.localizedDescription.contains("PRIVATE_SERVER_DETAIL"), file: file, line: line)
            XCTAssertFalse(error.localizedDescription.contains(token), file: file, line: line)
        }
    }

    func testEndpointAcceptsHTTPSOriginsAndOnlyOptedInLoopbackHTTP() throws {
        XCTAssertEqual(try PhotoAnalysisEndpoint.validated(" https://example.test \n").absoluteString, "https://example.test/v1/meal-analysis")
        XCTAssertEqual(try PhotoAnalysisEndpoint.validated("https://example.test:8443/").port, 8443)
        for origin in ["http://localhost:8787", "http://127.0.0.1:8787", "http://[::1]:8787"] {
            XCTAssertThrowsError(try PhotoAnalysisEndpoint.validated(origin))
            XCTAssertEqual(try PhotoAnalysisEndpoint.validated(origin, allowInsecureLoopback: true).path, "/v1/meal-analysis")
        }
        let invalid = [
            "", "example.test", "ftp://example.test", "http://example.test", "http://192.168.1.2:8787",
            "http://localhost.example.test", "http://127.0.0.2", "https://user@example.test",
            "https://user:pass@example.test", "https://example.test/custom", "https://example.test/v1/meal-analysis",
            "https://example.test?token=secret", "https://example.test#fragment", "https://example.test:0", "https://example.test:65536"
        ]
        for origin in invalid {
            XCTAssertThrowsError(try PhotoAnalysisEndpoint.validated(origin, allowInsecureLoopback: true)) { error in
                XCTAssertEqual(error as? PhotoServiceError, .configuration, origin)
            }
        }
    }

    func testRequestContainsBearerJPEGAndUnmodifiedHint() async throws {
        let harness = try PhotoTransportHarness(reply: .http(200, emptyResponse))
        defer { harness.close() }
        let hint = " 鶏肉・ごはんは半分。\nソースは別添え。 "
        let result = try await harness.transport.analyze(jpeg: jpeg, hint: hint, endpoint: harness.endpoint, token: token)
        XCTAssertTrue(result.items.isEmpty)
        XCTAssertEqual(result.note, "食品を確認できませんでした。")
        let request = try XCTUnwrap(harness.stub.requests.first)
        XCTAssertEqual(harness.stub.requests.count, 1)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.url, harness.endpoint)
        XCTAssertEqual(request.headers["Authorization"], "Bearer \(token)")
        XCTAssertEqual(request.headers["Content-Type"], "application/json")
        XCTAssertEqual(request.headers["Accept"], "application/json")
        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: request.body) as? [String: Any])
        XCTAssertEqual(Set(body.keys), ["imageBase64", "mimeType", "hint"])
        XCTAssertEqual(body["mimeType"] as? String, "image/jpeg")
        XCTAssertEqual(body["hint"] as? String, hint)
        XCTAssertEqual(Data(base64Encoded: try XCTUnwrap(body["imageBase64"] as? String)), jpeg)
        XCTAssertFalse(String(decoding: request.body, as: UTF8.self).contains(token))
    }

    func testInputValidationStopsRequestsBeforeAnyImageLeavesTheClient() async throws {
        let harness = try PhotoTransportHarness(reply: .http(200, emptyResponse))
        defer { harness.close() }
        for image in [Data(), Data([0xff, 0xd8, 0xff]), Data([1, 2, 3, 4]), Data([0xff, 0xd8, 1, 2])] {
            await assertFailure(.invalidImage) {
                try await harness.transport.analyze(jpeg: image, hint: "", endpoint: harness.endpoint, token: token)
            }
        }
        var oversized = Data([0xff, 0xd8])
        oversized.append(Data(repeating: 0, count: 4 * 1024 * 1024 - 3))
        oversized.append(contentsOf: [0xff, 0xd9])
        await assertFailure(.invalidImage) {
            try await harness.transport.analyze(jpeg: oversized, hint: "", endpoint: harness.endpoint, token: token)
        }
        await assertFailure(.invalidHint) {
            try await harness.transport.analyze(jpeg: jpeg, hint: String(repeating: "あ", count: 501), endpoint: harness.endpoint, token: token)
        }
        for invalidToken in ["", String(repeating: "a", count: 31), String(repeating: "a", count: 257), token + " ", token + "\n", String(repeating: "あ", count: 32)] {
            await assertFailure(.configuration) {
                try await harness.transport.analyze(jpeg: jpeg, hint: "", endpoint: harness.endpoint, token: invalidToken)
            }
        }
        XCTAssertTrue(harness.stub.requests.isEmpty)
    }

    func testMaximumImageHintAndTokenBoundsAreAccepted() async throws {
        let harness = try PhotoTransportHarness(reply: .http(200, emptyResponse))
        defer { harness.close() }
        var maximumImage = Data([0xff, 0xd8])
        maximumImage.append(Data(repeating: 0, count: 4 * 1024 * 1024 - 4))
        maximumImage.append(contentsOf: [0xff, 0xd9])
        let result = try await harness.transport.analyze(jpeg: maximumImage, hint: String(repeating: "あ", count: 500),
                                                        endpoint: harness.endpoint, token: String(repeating: "z", count: 256))
        XCTAssertTrue(result.items.isEmpty)
        XCTAssertEqual(harness.stub.requests.count, 1)
    }

    func testAnalyzeRejectsUnsafeOrUnexpectedEndpointURLs() async throws {
        let harness = try PhotoTransportHarness(reply: .http(200, emptyResponse))
        defer { harness.close() }
        let host = try XCTUnwrap(harness.endpoint.host)
        for value in ["http://\(host)/v1/meal-analysis", "https://\(host)/other", "https://\(host)/v1/meal-analysis?token=x", "https://u:p@\(host)/v1/meal-analysis"] {
            let url = try XCTUnwrap(URL(string: value))
            await assertFailure(.configuration) {
                try await harness.transport.analyze(jpeg: jpeg, hint: "", endpoint: url, token: token)
            }
        }
        XCTAssertTrue(harness.stub.requests.isEmpty)
    }

    func testValidSuccessPreservesUnknownNutrientsButMalformedSuccessIsRejected() async throws {
        let item = PhotoAnalysisItem(name: "スープ", serving: "1杯", nutrition: Nutrition(energy: 50, protein: 2, fat: 1, carbs: 8), confidence: .low, reason: "塩分は判別できない")
        let expected = PhotoAnalysisResult(items: [item], note: "概算です")
        let success = try PhotoTransportHarness(reply: .http(200, JSONEncoder().encode(expected)))
        defer { success.close() }
        let result = try await success.transport.analyze(jpeg: jpeg, hint: "", endpoint: success.endpoint, token: token)
        XCTAssertEqual(result, expected)
        XCTAssertNil(result.items[0].nutrition.fiber)
        XCTAssertNil(result.items[0].nutrition.salt)

        var invalidItem = item
        invalidItem.nutrition.energy = -1
        let invalidBodies = [
            Data("{PRIVATE_SERVER_DETAIL_do_not_display".utf8),
            Data("{\"items\":[],\"note\":42}".utf8),
            try JSONEncoder().encode(PhotoAnalysisResult(items: [invalidItem])),
            try JSONEncoder().encode(PhotoAnalysisResult(items: Array(repeating: item, count: 13)))
        ]
        for body in invalidBodies {
            let harness = try PhotoTransportHarness(reply: .http(200, body))
            defer { harness.close() }
            await assertFailure(.invalidResponse) {
                try await harness.transport.analyze(jpeg: jpeg, hint: "", endpoint: harness.endpoint, token: token)
            }
        }
    }

    func testHTTPStatusMappingNeverEchoesServerBodyOrToken() async throws {
        let cases: [(Int, PhotoServiceError)] = [
            (401, .unauthorized), (403, .unauthorized), (429, .rateLimited), (408, .timedOut), (504, .timedOut),
            (422, .refused), (400, .invalidImage), (413, .invalidImage), (415, .invalidImage),
            (500, .unavailable), (503, .unavailable), (302, .unavailable), (201, .unavailable)
        ]
        for (status, expected) in cases {
            let sensitive = Data("PRIVATE_SERVER_DETAIL token=\(token) imageBase64=private".utf8)
            let harness = try PhotoTransportHarness(reply: .http(status, sensitive))
            defer { harness.close() }
            await assertFailure(expected) {
                try await harness.transport.analyze(jpeg: jpeg, hint: "", endpoint: harness.endpoint, token: token)
            }
        }
    }

    func testURLTimeoutAndConnectionFailureMapToSafeErrors() async throws {
        for (code, expected) in [(URLError.Code.timedOut, PhotoServiceError.timedOut), (.cannotConnectToHost, .unavailable), (.notConnectedToInternet, .unavailable)] {
            let harness = try PhotoTransportHarness(reply: .failure(code))
            defer { harness.close() }
            await assertFailure(expected) {
                try await harness.transport.analyze(jpeg: jpeg, hint: "", endpoint: harness.endpoint, token: token)
            }
        }
    }

    func testCancelledURLRequestBecomesCancellationError() async throws {
        let harness = try PhotoTransportHarness(reply: .failure(.cancelled))
        defer { harness.close() }
        do {
            _ = try await harness.transport.analyze(jpeg: jpeg, hint: "", endpoint: harness.endpoint, token: token)
            XCTFail("Expected CancellationError")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }

    func testTaskCancellationBeforeRequestAndWhileWaiting() async throws {
        let ready = expectation(description: "URLProtocol received request")
        let stopped = expectation(description: "URLProtocol stopped on cancellation")
        let harness = try PhotoTransportHarness(reply: .waitForCancellation, onStart: { ready.fulfill() }, onStop: { stopped.fulfill() })
        defer { harness.close() }
        let beforeStart = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await harness.transport.analyze(jpeg: jpeg, hint: "", endpoint: harness.endpoint, token: token)
        }
        do { _ = try await beforeStart.value; XCTFail("Expected pre-request cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertTrue(harness.stub.requests.isEmpty)

        let running = Task { try await harness.transport.analyze(jpeg: jpeg, hint: "", endpoint: harness.endpoint, token: token) }
        await fulfillment(of: [ready], timeout: 2)
        running.cancel()
        do { _ = try await running.value; XCTFail("Expected in-flight cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        await fulfillment(of: [stopped], timeout: 2)
        XCTAssertEqual(harness.stub.requests.count, 1)
    }

    func testOversizedOrNonHTTPResponsesAreRejected() async throws {
        // Valid JSON padded above the cap must fail before accepting the otherwise valid result.
        var oversized = emptyResponse
        oversized.append(Data(repeating: 0x20, count: 128 * 1024 + 1 - oversized.count))
        for reply in [PhotoRequestStub.Reply.http(200, oversized), .nonHTTP(emptyResponse)] {
            let harness = try PhotoTransportHarness(reply: reply)
            defer { harness.close() }
            await assertFailure(.invalidResponse) {
                try await harness.transport.analyze(jpeg: jpeg, hint: "", endpoint: harness.endpoint, token: token)
            }
        }
    }
}
