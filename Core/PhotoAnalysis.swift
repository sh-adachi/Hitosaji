import Foundation

/// A qualitative assessment supplied by the photo analyzer, not a calibrated probability.
public enum PhotoConfidence: String, Codable, CaseIterable, Sendable {
    case high, medium, low

    public var label: String {
        switch self {
        case .high: "高"
        case .medium: "中"
        case .low: "低"
        }
    }
}

/// Nutrition is estimated for the complete serving visible in the photograph.
/// No identifier is encoded; a new diary identifier is created only when making meal entries.
public struct PhotoAnalysisItem: Codable, Equatable, Sendable {
    public var name: String
    public var serving: String
    public var nutrition: Nutrition
    public var confidence: PhotoConfidence
    public var reason: String

    public init(name: String, serving: String, nutrition: Nutrition, confidence: PhotoConfidence = .low, reason: String = "") {
        self.name = name
        self.serving = serving
        self.nutrition = nutrition
        self.confidence = confidence
        self.reason = reason
    }
}

public struct PhotoAnalysisResult: Codable, Equatable, Sendable {
    public var items: [PhotoAnalysisItem]
    public var note: String

    public init(items: [PhotoAnalysisItem] = [], note: String = "") {
        self.items = items
        self.note = note
    }

    /// Accepts at most 12 foods. An empty result means that no food could be identified.
    /// Unknown fiber/salt remain nil; malformed or out-of-bounds values are never repaired silently.
    public static func decodeValidated(_ data: Data) throws -> PhotoAnalysisResult {
        let result: PhotoAnalysisResult
        do {
            result = try JSONDecoder().decode(PhotoAnalysisResult.self, from: data)
        } catch {
            throw PhotoAnalysisError.invalidResponse
        }
        try result.validate()
        return result
    }

    /// Creates editable diary entries, without saving them. The caller owns user review and saving.
    /// Each analyzed visible serving maps to one portion of the supplied per-serving nutrition.
    public func mealEntries(date: Date, period: MealPeriod) throws -> [MealEntry] {
        try validate()
        let entries = items.map { item in
            var annotation = ["AI推定（確かさ：\(item.confidence.label)）"]
            let reason = item.reason.trimmingCharacters(in: .whitespacesAndNewlines)
            let sharedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
            if !reason.isEmpty { annotation.append("推定理由：\(reason)") }
            if !sharedNote.isEmpty { annotation.append("写真全体の補足：\(sharedNote)") }
            return MealEntry(date: date, period: period, foodName: item.name, serving: item.serving,
                             portions: 1, nutrition: item.nutrition, note: annotation.joined(separator: "\n"))
        }
        // Validate again after mapping, including the requested date and combined annotation.
        try Validation.validate(AppData(entries: entries))
        return entries
    }

    private func validate() throws {
        guard items.count <= 12 else { throw PhotoAnalysisError.tooManyItems }
        guard note.count <= 1_000 else { throw PhotoAnalysisError.textTooLong("写真全体の補足") }
        for item in items {
            guard item.reason.count <= 500 else { throw PhotoAnalysisError.textTooLong("推定理由") }
        }
        // Reuse the diary's finite/nonnegative nutrient and nonblank name/serving bounds.
        let entries = items.map {
            MealEntry(foodName: $0.name, serving: $0.serving, portions: 1, nutrition: $0.nutrition)
        }
        try Validation.validate(AppData(entries: entries))
    }
}

public enum PhotoAnalysisError: Error, LocalizedError, Equatable {
    case invalidResponse
    case tooManyItems
    case textTooLong(String)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "写真の解析結果を読み取れませんでした。もう一度お試しください。"
        case .tooManyItems:
            "解析結果が12品を超えています。料理を分けて撮影してください。"
        case .textTooLong(let field):
            "\(field)が長すぎます。解析結果を確認してください。"
        }
    }
}
