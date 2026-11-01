import Foundation

/// Nutrient quantities for one serving. Energy is kcal; all other values are grams.
/// An absent fiber/salt value means unknown, not zero.
public struct Nutrition: Codable, Equatable, Sendable {
    public var energy: Double
    public var protein: Double
    public var fat: Double
    public var carbs: Double
    public var fiber: Double?
    public var salt: Double?

    public init(energy: Double = 0, protein: Double = 0, fat: Double = 0, carbs: Double = 0, fiber: Double? = nil, salt: Double? = nil) {
        self.energy = energy
        self.protein = protein
        self.fat = fat
        self.carbs = carbs
        self.fiber = fiber
        self.salt = salt
    }

    public func scaled(by multiplier: Double) -> Nutrition {
        Nutrition(energy: energy * multiplier, protein: protein * multiplier,
                  fat: fat * multiplier, carbs: carbs * multiplier,
                  fiber: fiber.map { $0 * multiplier }, salt: salt.map { $0 * multiplier })
    }
}

public enum MealPeriod: String, CaseIterable, Codable, Identifiable, Sendable {
    case breakfast, lunch, dinner, snack
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .breakfast: "朝食"
        case .lunch: "昼食"
        case .dinner: "夕食"
        case .snack: "間食"
        }
    }
    public var symbol: String {
        switch self {
        case .breakfast: "sunrise.fill"
        case .lunch: "sun.max.fill"
        case .dinner: "moon.stars.fill"
        case .snack: "cup.and.saucer.fill"
        }
    }
}

public struct Food: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var serving: String
    public var nutrition: Nutrition
    public var isCustom: Bool
    public var source: String

    public init(id: UUID = UUID(), name: String, serving: String, nutrition: Nutrition = Nutrition(), isCustom: Bool = false, source: String = "手入力") {
        self.id = id
        self.name = name
        self.serving = serving
        self.nutrition = nutrition
        self.isCustom = isCustom
        self.source = source
    }
}

public struct MealEntry: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    private var day: DiaryDay
    /// The chosen diary day at current local midnight. Time of day is intentionally discarded.
    public var date: Date {
        get { day.date }
        set { day = DiaryDay(newValue) }
    }
    public var period: MealPeriod
    public var foodName: String
    public var serving: String
    public var portions: Double
    /// Per-serving nutrition; `total` applies the recorded portion count.
    public var nutrition: Nutrition
    public var note: String
    public var total: Nutrition { nutrition.scaled(by: portions) }

    public init(id: UUID = UUID(), date: Date = Date(), period: MealPeriod = .breakfast, foodName: String, serving: String = "1食", portions: Double = 1, nutrition: Nutrition = Nutrition(), note: String = "") {
        self.id = id
        self.day = DiaryDay(date)
        self.period = period
        self.foodName = foodName
        self.serving = serving
        self.portions = portions
        self.nutrition = nutrition
        self.note = note
    }

    private enum CodingKeys: String, CodingKey {
        case id, day, date, period, foodName, serving, portions, nutrition, note
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        if container.contains(.day) {
            day = try container.decode(DiaryDay.self, forKey: .day)
        } else {
            // Legacy absolute dates have no original zone; migrate once in the current zone.
            day = DiaryDay(try container.decode(Date.self, forKey: .date))
            guard day.date.timeIntervalSinceReferenceDate.isFinite else {
                throw DecodingError.dataCorruptedError(forKey: .date, in: container, debugDescription: "Invalid legacy diary date.")
            }
        }
        period = try container.decode(MealPeriod.self, forKey: .period)
        foodName = try container.decode(String.self, forKey: .foodName)
        serving = try container.decode(String.self, forKey: .serving)
        portions = try container.decode(Double.self, forKey: .portions)
        nutrition = try container.decode(Nutrition.self, forKey: .nutrition)
        note = try container.decode(String.self, forKey: .note)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(day, forKey: .day)
        try container.encode(period, forKey: .period)
        try container.encode(foodName, forKey: .foodName)
        try container.encode(serving, forKey: .serving)
        try container.encode(portions, forKey: .portions)
        try container.encode(nutrition, forKey: .nutrition)
        try container.encode(note, forKey: .note)
    }
}

public struct WeightEntry: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    private var day: DiaryDay
    /// The chosen diary day at current local midnight. Time of day is intentionally discarded.
    public var date: Date {
        get { day.date }
        set { day = DiaryDay(newValue) }
    }
    public var kilograms: Double

    public init(id: UUID = UUID(), date: Date = Date(), kilograms: Double) {
        self.id = id
        self.day = DiaryDay(date)
        self.kilograms = kilograms
    }

    private enum CodingKeys: String, CodingKey { case id, day, date, kilograms }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        if container.contains(.day) {
            day = try container.decode(DiaryDay.self, forKey: .day)
        } else {
            day = DiaryDay(try container.decode(Date.self, forKey: .date))
            guard day.date.timeIntervalSinceReferenceDate.isFinite else {
                throw DecodingError.dataCorruptedError(forKey: .date, in: container, debugDescription: "Invalid legacy diary date.")
            }
        }
        kilograms = try container.decode(Double.self, forKey: .kilograms)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(day, forKey: .day)
        try container.encode(kilograms, forKey: .kilograms)
    }
}

public struct NutritionGoals: Codable, Equatable, Sendable {
    public var energy: Double
    public var protein: Double
    public var fat: Double
    public var carbs: Double
    public var fiber: Double
    public var salt: Double
    public var isExample: Bool

    public init(energy: Double = 2000, protein: Double = 75, fat: Double = 55, carbs: Double = 280, fiber: Double = 20, salt: Double = 6.5, isExample: Bool = true) {
        self.energy = energy
        self.protein = protein
        self.fat = fat
        self.carbs = carbs
        self.fiber = fiber
        self.salt = salt
        self.isExample = isExample
    }

    /// UI placeholders only. These are not personalized dietary recommendations.
    public static let example = NutritionGoals()
}

public struct AppData: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var entries: [MealEntry]
    public var weights: [WeightEntry]
    public var customFoods: [Food]
    public var goals: NutritionGoals

    public init(schemaVersion: Int = 1, entries: [MealEntry] = [], weights: [WeightEntry] = [], customFoods: [Food] = [], goals: NutritionGoals = .example) {
        self.schemaVersion = schemaVersion
        self.entries = entries
        self.weights = weights
        self.customFoods = customFoods
        self.goals = goals
    }
}

public struct DailySummary: Identifiable, Equatable, Sendable {
    public var id: Date { date }
    public var date: Date
    public var nutrition: Nutrition
    public var isRecorded: Bool

    public init(date: Date, nutrition: Nutrition = Nutrition(), isRecorded: Bool = false) {
        self.date = date
        self.nutrition = nutrition
        self.isRecorded = isRecorded
    }
}
