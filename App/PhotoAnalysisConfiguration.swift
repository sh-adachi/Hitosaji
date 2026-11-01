import Foundation
import Security

struct PhotoAnalysisConfiguration: Codable {
    var serverURL: String
    var token: String

    static var isConfigured: Bool { (try? load()) != nil || isFixture }
    static var isFixture: Bool {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        return args.contains("--uitesting") && args.contains("--photo-fixture")
        #else
        return false
        #endif
    }

    var endpoint: URL {
        get throws {
            #if DEBUG
            return try PhotoAnalysisEndpoint.validated(serverURL, allowInsecureLoopback: true)
            #else
            return try PhotoAnalysisEndpoint.validated(serverURL)
            #endif
        }
    }

    private static var query: [String: Any] {
        let testing = ProcessInfo.processInfo.arguments.contains("--uitesting")
        return [kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: "dev.adachi.hitosaji.photo-analysis",
                kSecAttrAccount as String: testing ? "configuration-tests" : "configuration"]
    }

    static func load() throws -> Self {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let config = try? JSONDecoder().decode(Self.self, from: data) else { throw PhotoServiceError.configuration }
        _ = try config.endpoint
        return config
    }

    func save() throws {
        _ = try endpoint
        guard token.utf8.count >= 32, token.utf8.count <= 256,
              token.range(of: "^[A-Za-z0-9._~-]+$", options: .regularExpression) != nil else { throw PhotoServiceError.configuration }
        let data = try JSONEncoder().encode(self)
        let attributes: [String: Any] = [kSecValueData as String: data,
                                        kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(Self.query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let insertion = Self.query.merging(attributes, uniquingKeysWith: { _, rhs in rhs })
            guard SecItemAdd(insertion as CFDictionary, nil) == errSecSuccess else { throw PhotoConfigurationError.keychain }
        } else if status != errSecSuccess { throw PhotoConfigurationError.keychain }
    }

    static func remove() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw PhotoConfigurationError.keychain }
    }
}

enum PhotoConfigurationError: Error, LocalizedError {
    case keychain
    var errorDescription: String? { "接続設定を保存できませんでした。端末のロックを解除して、もう一度お試しください。" }
}

struct PhotoAnalysisClient {
    func analyze(jpeg: Data, hint: String) async throws -> PhotoAnalysisResult {
        #if DEBUG
        if PhotoAnalysisConfiguration.isFixture {
            try await Task.sleep(for: .milliseconds(700))
            let args = ProcessInfo.processInfo.arguments
            if args.contains("--photo-fixture-error") { throw PhotoServiceError.unavailable }
            if args.contains("--photo-fixture-empty") {
                return PhotoAnalysisResult(items: [], note: "食事を確認できませんでした。明るい場所で撮り直してください。")
            }
            return PhotoAnalysisResult(items: [
                PhotoAnalysisItem(name: "ごはん", serving: "茶碗1杯・150g（推定）", nutrition: Nutrition(energy: 234, protein: 3.8, fat: 0.5, carbs: 55.7), confidence: .medium, reason: "茶碗の大きさから推定しました。"),
                PhotoAnalysisItem(name: "焼き鮭", serving: "1切れ・80g（推定）", nutrition: Nutrition(energy: 180, protein: 20, fat: 11, carbs: 0.2), confidence: .low, reason: "調味料の量は写真から分かりません。")
            ], note: "これは画面テスト用の架空の解析結果です。")
        }
        #endif
        let config = try PhotoAnalysisConfiguration.load()
        return try await PhotoAnalysisTransport().analyze(jpeg: jpeg, hint: hint, endpoint: config.endpoint, token: config.token)
    }
}
