import Foundation

/// A small, original set of approximate examples. Check product labels for actual values.
/// These values are not copied from a commercial food database.
public enum FoodCatalog {
    public static let referenceSource = "一般的な食品の参考値。商品・調理方法で異なります。"

    public static let foods: [Food] = [
        item(1, "ごはん", "茶碗1杯・150g", 234, 3.8, 0.5, 55.7, 2.3, 0),
        item(2, "玄米ごはん", "茶碗1杯・150g", 228, 4.2, 1.5, 53.4, 2.1, 0),
        item(3, "食パン", "6枚切り1枚・60g", 149, 5.3, 2.5, 27.8, 2.5, 0.7),
        item(4, "オートミール", "乾燥30g", 105, 4.1, 1.7, 20.7, 2.8, 0),
        item(5, "うどん（ゆで）", "1玉・200g／つゆなし", 190, 5.2, 0.8, 43.2, 2.6, 0.6),
        item(6, "鶏むね肉（皮なし）", "加熱前100g", 105, 23.3, 1.9, 0, 0, 0.1),
        item(7, "鶏もも肉（皮つき）", "加熱前100g", 190, 16.6, 14.2, 0, 0, 0.2),
        item(8, "鮭の塩焼き", "1切れ・80g", 160, 18, 9, 0.2, 0, 1.2),
        item(9, "ゆで卵", "1個・50g", 67, 6.3, 5.2, 0.2, 0, 0.2),
        item(10, "納豆", "1パック・45g／たれなし", 83, 7.4, 4.5, 5.4, 3, 0),
        item(11, "木綿豆腐", "半丁・150g", 110, 10.5, 7.4, 2.3, 1.7, 0),
        item(12, "プレーンヨーグルト", "100g／無糖", 56, 3.6, 3, 4.9, 0, 0.1),
        item(13, "牛乳", "コップ1杯・200ml", 122, 6.6, 7.6, 9.6, 0, 0.2),
        item(14, "バナナ", "1本・可食部100g", 93, 1.1, 0.2, 22.5, 1.1, 0),
        item(15, "りんご", "半分・可食部125g", 70, 0.3, 0.4, 20, 2.4, 0),
        item(16, "ブロッコリー（ゆで）", "小鉢1皿・80g", 24, 3.1, 0.3, 4.2, 3.4, 0),
        item(17, "グリーンサラダ", "1皿・100g／ドレッシングなし", 22, 1.2, 0.2, 4.6, 1.6, 0),
        item(18, "豆腐とわかめのみそ汁", "1杯・180ml", 45, 3.5, 1.8, 3.7, 1, 1.5),
        item(19, "素焼きアーモンド", "約10粒・12g", 73, 2.4, 6.5, 2.5, 1.3, 0),
        item(20, "ブラックコーヒー", "1杯・150ml", 6, 0.3, 0, 1.1, 0, 0)
    ]

    private static func item(_ index: Int, _ name: String, _ serving: String, _ energy: Double, _ protein: Double, _ fat: Double, _ carbs: Double, _ fiber: Double, _ salt: Double) -> Food {
        // Stable identifiers keep saved/favorite selections meaningful between launches.
        let suffix = String(format: "%012d", index)
        let id = UUID(uuidString: "00000000-0000-4000-8000-" + suffix)!
        return Food(id: id, name: name, serving: serving,
                    nutrition: Nutrition(energy: energy, protein: protein, fat: fat, carbs: carbs, fiber: fiber, salt: salt),
                    source: referenceSource)
    }
}

public enum DemoData {
    /// Fictional records created only when the user explicitly chooses to explore demo data.
    public static func make(now: Date = Date()) -> AppData {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        var result = AppData()

        func append(_ index: Int, on day: Date, period: MealPeriod, hour: Int, portions: Double = 1) {
            let food = FoodCatalog.foods[index - 1]
            let date = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
            result.entries.append(MealEntry(date: date, period: period, foodName: food.name,
                serving: food.serving, portions: portions, nutrition: food.nutrition, note: "デモの記録"))
        }

        for offset in (0..<7).reversed() {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            append(3, on: day, period: .breakfast, hour: 8, portions: 1.5)
            append(9, on: day, period: .breakfast, hour: 8)
            append(12, on: day, period: .breakfast, hour: 8)
            append(14, on: day, period: .breakfast, hour: 8)
            append(1, on: day, period: .lunch, hour: 12)
            append(6, on: day, period: .lunch, hour: 12, portions: 1.5)
            append(16, on: day, period: .lunch, hour: 12)
            append(18, on: day, period: .lunch, hour: 12)
            if offset > 0 {
                append(2, on: day, period: .dinner, hour: 19, portions: offset.isMultiple(of: 2) ? 1.2 : 1)
                append(8, on: day, period: .dinner, hour: 19)
                append(11, on: day, period: .dinner, hour: 19)
                append(17, on: day, period: .dinner, hour: 19)
                append(19, on: day, period: .snack, hour: 15, portions: offset.isMultiple(of: 2) ? 1 : 2)
            }
            result.weights.append(WeightEntry(date: day, kilograms: 62.4 + Double(offset) * 0.1))
        }
        return result
    }
}
