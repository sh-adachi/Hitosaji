import Foundation

public enum NutritionDataError: Error, LocalizedError, Equatable {
    case unsupportedSchema(Int)
    case invalidValue(String)
    case duplicateIdentifier(String)
    case unreadableData

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let version): "保存データの形式（バージョン \(version)）には対応していません。"
        case .invalidValue(let field): "\(field)の値を確認してください。"
        case .duplicateIdentifier(let collection): "\(collection)に重複した記録があります。"
        case .unreadableData: "保存データを読み込めませんでした。元のファイルを保護するため、上書きしていません。"
        }
    }
}

public enum Validation {
    /// Broad input limits prevent mistakes/overflow, rather than providing dietary guidance.
    /// Per serving: 0...20,000 kcal; P/F/C/fiber 0...2,000 g; salt 0...200 g.
    /// Portions: >0...100; body weight: >0...500 kg. Goals use the same nutrient limits and must be positive.
    /// Names/servings must contain text (max 200 chars); notes max 2,000; sources max 500.
    /// Diary dates are Gregorian calendar days in years 0001...9999; times are not retained.
    public static func validate(_ data: AppData) throws {
        guard data.schemaVersion == 1 else { throw NutritionDataError.unsupportedSchema(data.schemaVersion) }
        try unique(data.entries.map(\.id), label: "食事")
        try unique(data.weights.map(\.id), label: "体重")
        try unique(data.customFoods.map(\.id), label: "マイ食品")
        for entry in data.entries {
            try date(entry.date)
            try text(entry.foodName, label: "食品名", maximum: 200)
            try text(entry.serving, label: "1食の量", maximum: 200)
            try number(entry.portions, label: "食べた量", maximum: 100, positive: true)
            try nutrients(entry.nutrition)
            guard entry.note.count <= 2_000 else { throw NutritionDataError.invalidValue("メモ") }
        }
        for weight in data.weights {
            try date(weight.date)
            try number(weight.kilograms, label: "体重", maximum: 500, positive: true)
        }
        for food in data.customFoods {
            try text(food.name, label: "食品名", maximum: 200)
            try text(food.serving, label: "1食の量", maximum: 200)
            try nutrients(food.nutrition)
            guard food.source.count <= 500 else { throw NutritionDataError.invalidValue("食品の情報元") }
        }
        try number(data.goals.energy, label: "目標エネルギー", maximum: 20_000, positive: true)
        try number(data.goals.protein, label: "目標たんぱく質", maximum: 2_000, positive: true)
        try number(data.goals.fat, label: "目標脂質", maximum: 2_000, positive: true)
        try number(data.goals.carbs, label: "目標炭水化物", maximum: 2_000, positive: true)
        try number(data.goals.fiber, label: "目標食物繊維", maximum: 2_000, positive: true)
        try number(data.goals.salt, label: "食塩の上限", maximum: 200, positive: true)
    }

    private static func nutrients(_ nutrition: Nutrition) throws {
        try number(nutrition.energy, label: "エネルギー", maximum: 20_000)
        try number(nutrition.protein, label: "たんぱく質", maximum: 2_000)
        try number(nutrition.fat, label: "脂質", maximum: 2_000)
        try number(nutrition.carbs, label: "炭水化物", maximum: 2_000)
        if let fiber = nutrition.fiber { try number(fiber, label: "食物繊維", maximum: 2_000) }
        if let salt = nutrition.salt { try number(salt, label: "食塩相当量", maximum: 200) }
    }

    private static func number(_ value: Double, label: String, maximum: Double, positive: Bool = false) throws {
        guard value.isFinite, value >= 0, value <= maximum, !positive || value > 0 else {
            throw NutritionDataError.invalidValue(label)
        }
    }

    private static func text(_ value: String, label: String, maximum: Int) throws {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, value.count <= maximum else {
            throw NutritionDataError.invalidValue(label)
        }
    }

    private static func date(_ value: Date) throws {
        guard value.timeIntervalSinceReferenceDate.isFinite else { throw NutritionDataError.invalidValue("日付") }
    }

    private static func unique(_ identifiers: [UUID], label: String) throws {
        guard Set(identifiers).count == identifiers.count else { throw NutritionDataError.duplicateIdentifier(label) }
    }
}
