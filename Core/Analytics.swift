import Foundation

public enum NutritionAnalytics {
    public static func entries(on date: Date, in entries: [MealEntry], calendar: Calendar = .current) -> [MealEntry] {
        entries.filter { calendar.isDate($0.date, inSameDayAs: date) }.sorted { $0.date < $1.date }
    }

    public static func total(_ entries: [MealEntry]) -> Nutrition {
        guard !entries.isEmpty else { return Nutrition() }
        var result = Nutrition(fiber: 0, salt: 0)
        for entry in entries {
            let amount = entry.total
            result.energy += amount.energy
            result.protein += amount.protein
            result.fat += amount.fat
            result.carbs += amount.carbs
            if let current = result.fiber, let fiber = amount.fiber { result.fiber = current + fiber }
            else { result.fiber = nil }
            if let current = result.salt, let salt = amount.salt { result.salt = current + salt }
            else { result.salt = nil }
        }
        return result
    }

    public static func recordedDays(in entries: [MealEntry], calendar: Calendar = .current) -> Int {
        Set(entries.map { calendar.startOfDay(for: $0.date) }).count
    }

    /// Consecutive calendar days, oldest first. Unrecorded days are distinguishable from recorded zeroes.
    public static func dailySummaries(ending date: Date, days: Int, entries: [MealEntry], calendar: Calendar = .current) -> [DailySummary] {
        guard days > 0 else { return [] }
        let end = calendar.startOfDay(for: date)
        return (0..<days).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: end) else { return nil }
            let daily = self.entries(on: day, in: entries, calendar: calendar)
            return DailySummary(date: day, nutrition: total(daily), isRecorded: !daily.isEmpty)
        }
    }
}
