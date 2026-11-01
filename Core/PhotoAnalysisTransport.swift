import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum PhotoServiceError: Error, LocalizedError, Equatable {
    case configuration, invalidImage, invalidHint, unauthorized, rateLimited, unavailable, timedOut, invalidResponse, refused

    public var errorDescription: String? {
        switch self {
        case .configuration: "設定から写真解析の接続先とアクセストークンを登録してください。"
        case .invalidImage: "写真を読み込めませんでした。別の写真を選んでください。"
        case .invalidHint: "写真の補足は500文字以内で入力してください。"
        case .unauthorized: "解析サービスに接続できません。設定のアクセストークンを確認してください。"
        case .rateLimited: "解析が混み合っています。少し時間をおいて、もう一度お試しください。"
        case .unavailable: "解析サービスに接続できませんでした。通信状態と接続先を確認して、もう一度お試しください。"
        case .timedOut: "解析に時間がかかっています。もう一度お試しください。"
        case .invalidResponse: "解析結果を読み取れませんでした。別の写真でお試しいただくか、手入力してください。"
        case .refused: "この写真は解析できませんでした。食事がはっきり写った写真を選んでください。"
        }
    }
}

public enum PhotoAnalysisEndpoint {
    /// HTTP is accepted only for explicit loopback development, never arbitrary LAN hosts.
    public static func validated(_ string: String, allowInsecureLoopback: Bool = false) throws -> URL {
        guard let components = URLComponents(string: string.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = components.scheme?.lowercased(), let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              components.path.isEmpty || components.path == "/",
              components.port.map({ (1...65535).contains($0) }) ?? true,
              scheme == "https" || (allowInsecureLoopback && scheme == "http" && ["localhost", "127.0.0.1", "[::1]", "::1"].contains(host.lowercased())),
              let url = components.url else { throw PhotoServiceError.configuration }
        return url.appendingPathComponent("v1/meal-analysis")
    }
}

private final class RejectPhotoRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        // A redirect must never forward a private image or bearer token to a different destination.
        completionHandler(nil)
    }
}

public final class PhotoAnalysisTransport: Sendable {
    private let session: URLSession
    private let ownsSession: Bool

    public init(session: URLSession? = nil) {
        ownsSession = session == nil
        if let session { self.session = session }
        else {
            let config = URLSessionConfiguration.ephemeral
            config.urlCache = nil
            config.httpCookieStorage = nil
            config.httpShouldSetCookies = false
            config.timeoutIntervalForRequest = 75
            config.timeoutIntervalForResource = 90
            self.session = URLSession(configuration: config, delegate: RejectPhotoRedirects(), delegateQueue: nil)
        }
    }

    deinit { if ownsSession { session.invalidateAndCancel() } }

    public func analyze(jpeg: Data, hint: String, endpoint: URL, token: String) async throws -> PhotoAnalysisResult {
        guard var base = URLComponents(url: endpoint, resolvingAgainstBaseURL: false),
              base.path == "/v1/meal-analysis" else { throw PhotoServiceError.configuration }
        base.path = ""
        #if DEBUG
        let verified = try PhotoAnalysisEndpoint.validated(base.string ?? "", allowInsecureLoopback: true)
        #else
        let verified = try PhotoAnalysisEndpoint.validated(base.string ?? "")
        #endif
        guard verified == endpoint else { throw PhotoServiceError.configuration }
        guard jpeg.count >= 4, jpeg.count <= 4 * 1024 * 1024,
              jpeg.starts(with: [0xff, 0xd8]), jpeg.suffix(2) == Data([0xff, 0xd9]) else { throw PhotoServiceError.invalidImage }
        guard hint.count <= 500 else { throw PhotoServiceError.invalidHint }
        guard token.utf8.count >= 32, token.utf8.count <= 256,
              token.range(of: "^[A-Za-z0-9._~-]+$", options: .regularExpression) != nil else { throw PhotoServiceError.configuration }
        struct Payload: Encodable { let imageBase64: String; let mimeType: String; let hint: String }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpBody = try JSONEncoder().encode(Payload(imageBase64: jpeg.base64EncodedString(), mimeType: "image/jpeg", hint: hint))
        do {
            try Task.checkCancellation()
            let (data, response) = try await session.data(for: request)
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse else { throw PhotoServiceError.invalidResponse }
            switch http.statusCode {
            case 200:
                guard data.count <= 128 * 1024 else { throw PhotoServiceError.invalidResponse }
                do { return try PhotoAnalysisResult.decodeValidated(data) }
                catch { throw PhotoServiceError.invalidResponse }
            case 401, 403: throw PhotoServiceError.unauthorized
            case 429: throw PhotoServiceError.rateLimited
            case 408, 504: throw PhotoServiceError.timedOut
            case 422: throw PhotoServiceError.refused
            case 400, 413, 415: throw PhotoServiceError.invalidImage
            default: throw PhotoServiceError.unavailable
            }
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            throw error.code == .timedOut ? PhotoServiceError.timedOut : PhotoServiceError.unavailable
        }
    }
}
