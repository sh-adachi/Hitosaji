import Foundation

/// Local JSON storage. Call serially (for example from a main-actor store).
/// Existing data must decode and validate before a save can replace it.
public struct NutritionRepository: Sendable {
    public let directory: URL
    public var fileURL: URL { directory.appendingPathComponent("data.json") }
    public var backupURL: URL { directory.appendingPathComponent("data.backup.json") }

    public init(directory: URL) { self.directory = directory }

    public func load() throws -> AppData {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return AppData() }
        return try decode(Data(contentsOf: fileURL))
    }

    public func save(_ data: AppData) throws {
        try Validation.validate(data)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        // Kept for migration of legacy absolute dates; new diary records encode a civil-day key.
        encoder.dateEncodingStrategy = .deferredToDate
        let encoded = try encoder.encode(data)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let previous = try Data(contentsOf: fileURL)
            _ = try decode(previous)
            // If preserving the previous content fails, keep the primary untouched.
            try previous.write(to: backupURL, options: .atomic)
        }
        try encoded.write(to: fileURL, options: .atomic)
    }

    private func decode(_ data: Data) throws -> AppData {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .deferredToDate
        let decoded: AppData
        do { decoded = try decoder.decode(AppData.self, from: data) }
        catch { throw NutritionDataError.unreadableData }
        try Validation.validate(decoded)
        return decoded
    }
}
