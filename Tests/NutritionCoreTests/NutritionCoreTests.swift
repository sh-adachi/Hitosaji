import Foundation
import XCTest
@testable import NutritionCore

final class NutritionCoreTests: XCTestCase {
    private var tokyo: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }

    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }

    func testPortionsAndEditingRecalculateFromPerServingValues() throws {
        var entry = MealEntry(foodName: "ごはん", portions: 0.5,
            nutrition: Nutrition(energy: 234, protein: 3.8, fat: 0.5, carbs: 55.7, fiber: 2.3, salt: 0))
        XCTAssertEqual(entry.total.energy, 117)
        entry.portions = 2
        XCTAssertEqual(entry.total.energy, 468)
        XCTAssertEqual(entry.nutrition.energy, 234)
        entry.nutrition.energy = 250
        XCTAssertEqual(entry.total.energy, 500)
        var data = AppData(entries: [entry])
        let originalID = entry.id
        data.entries[0].period = .dinner
        data.entries[0].foodName = "玄米ごはん"
        XCTAssertEqual(data.entries[0].id, originalID)
        XCTAssertEqual(data.entries.count, 1)
        try Validation.validate(data)
    }

    func testJapaneseDayBoundariesAndMissingDays() {
        let originalZone = NSTimeZone.default
        NSTimeZone.default = tokyo.timeZone
        defer { NSTimeZone.default = originalZone }
        let before = MealEntry(date: date("2026-09-30T14:59:59Z"), foodName: "前日", nutrition: Nutrition(energy: 10))
        let after = MealEntry(date: date("2026-09-30T15:00:00Z"), foodName: "当日", nutrition: Nutrition(energy: 20))
        let later = MealEntry(date: date("2026-10-01T14:59:59Z"), foodName: "当日夜", portions: 2, nutrition: Nutrition(energy: 30))
        let tomorrow = MealEntry(date: date("2026-10-01T15:00:00Z"), foodName: "翌日", nutrition: Nutrition(energy: 40))
        let entries = [tomorrow, after, later, before]
        let day = date("2026-10-01T03:00:00Z")
        let daily = NutritionAnalytics.entries(on: day, in: entries, calendar: tokyo)
        XCTAssertEqual(daily.map(\.id), [after.id, later.id])
        XCTAssertEqual(NutritionAnalytics.total(daily).energy, 80)
        XCTAssertEqual(NutritionAnalytics.recordedDays(in: entries, calendar: tokyo), 3)
        let summaries = NutritionAnalytics.dailySummaries(ending: day, days: 3, entries: entries, calendar: tokyo)
        XCTAssertEqual(summaries.map(\.isRecorded), [false, true, true])
        XCTAssertEqual(summaries.map(\.nutrition.energy), [0, 10, 80])
        XCTAssertEqual(Set(summaries.map(\.id)).count, 3)
        XCTAssertTrue(NutritionAnalytics.dailySummaries(ending: day, days: 0, entries: entries).isEmpty)
        XCTAssertTrue(NutritionAnalytics.dailySummaries(ending: day, days: -1, entries: entries).isEmpty)
    }

    func testCalendarDaysAcrossDaylightSavingTransition() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let summaries = NutritionAnalytics.dailySummaries(ending: date("2026-03-09T12:00:00Z"), days: 3, entries: [], calendar: calendar)
        XCTAssertEqual(summaries.map { calendar.component(.day, from: $0.date) }, [7, 8, 9])
        XCTAssertEqual(summaries[2].date.timeIntervalSince(summaries[1].date), 23 * 3600)
    }

    func testUnknownNutrientsStayUnknownWithoutLosingKnownNutrients() {
        let first = MealEntry(foodName: "食品1", portions: 2, nutrition: Nutrition(energy: 100, fiber: 2, salt: 0.5))
        let missingFiber = MealEntry(foodName: "食品2", nutrition: Nutrition(energy: 150, fiber: nil, salt: 0.2))
        let total = NutritionAnalytics.total([first, missingFiber])
        XCTAssertEqual(total.energy, 350)
        XCTAssertNil(total.fiber)
        XCTAssertEqual(total.salt!, 1.2, accuracy: 0.00001)
        let missingSalt = MealEntry(foodName: "食品3", nutrition: Nutrition(fiber: 1))
        XCTAssertNil(NutritionAnalytics.total([missingSalt, first]).salt)
        XCTAssertEqual(NutritionAnalytics.total([missingSalt, first]).fiber, 5)
        XCTAssertNil(NutritionAnalytics.total([]).fiber)
        XCTAssertNil(NutritionAnalytics.total([]).salt)
    }

    func testValidationRejectsInvalidNumbersAndDuplicates() throws {
        for invalid in [Double.nan, .infinity, -.infinity, -1, 20_001] {
            let entry = MealEntry(foodName: "食品", nutrition: Nutrition(energy: invalid))
            XCTAssertThrowsError(try Validation.validate(AppData(entries: [entry])))
        }
        for invalid in [Double.nan, 0, -1, 101] {
            XCTAssertThrowsError(try Validation.validate(AppData(entries: [MealEntry(foodName: "食品", portions: invalid)])))
        }
        XCTAssertThrowsError(try Validation.validate(AppData(weights: [WeightEntry(kilograms: 0)])))
        XCTAssertThrowsError(try Validation.validate(AppData(weights: [WeightEntry(kilograms: 501)])))
        XCTAssertThrowsError(try Validation.validate(AppData(entries: [MealEntry(foodName: " \n ")])))
        let entry = MealEntry(foodName: "食品")
        XCTAssertThrowsError(try Validation.validate(AppData(entries: [entry, entry])))
        var goals = NutritionGoals.example
        goals.salt = 0
        XCTAssertThrowsError(try Validation.validate(AppData(goals: goals)))
        try Validation.validate(AppData(entries: [MealEntry(foodName: "食品", nutrition: Nutrition())]))
    }

    func testCatalogAndDemoAreValidAndCatalogIdentifiersAreStable() throws {
        XCTAssertEqual(FoodCatalog.foods.count, 20)
        XCTAssertEqual(Set(FoodCatalog.foods.map(\.id)).count, 20)
        XCTAssertTrue(FoodCatalog.foods.allSatisfy { !$0.serving.isEmpty && $0.source == FoodCatalog.referenceSource })
        try Validation.validate(AppData(customFoods: FoodCatalog.foods))
        let demo = DemoData.make(now: date("2026-10-01T03:00:00Z"))
        try Validation.validate(demo)
        XCTAssertEqual(NutritionAnalytics.recordedDays(in: demo.entries), 7)
        XCTAssertEqual(demo.weights.count, 7)
        XCTAssertTrue(demo.goals.isExample)
        XCTAssertTrue(AppData().entries.isEmpty)
    }
}
