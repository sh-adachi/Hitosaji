import Foundation
import XCTest
@testable import NutritionCore

final class DiaryDayTests: XCTestCase {
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }

    private func withTimeZone<T>(_ identifier: String, _ body: () throws -> T) rethrows -> T {
        let original = NSTimeZone.default
        NSTimeZone.default = TimeZone(identifier: identifier)!
        defer { NSTimeZone.default = original }
        return try body()
    }

    private func dayString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = Calendar.current.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func withRepository(_ body: (NutritionRepository) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("HitosajiDateTests-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(NutritionRepository(directory: directory))
    }

    func testSavedAndInMemoryDiaryDaysSurviveTimeZoneChange() throws {
        try withRepository { repository in
            let original = try withTimeZone("Asia/Tokyo") {
                let chosen = date("2026-09-30T15:05:00Z") // October 1, 00:05 in Tokyo.
                let data = AppData(entries: [MealEntry(date: chosen, period: .dinner, foodName: "食品", nutrition: Nutrition(energy: 200))],
                                   weights: [WeightEntry(date: chosen, kilograms: 62.3)])
                try repository.save(data)
                XCTAssertEqual(dayString(data.entries[0].date), "2026-10-01")
                return data
            }

            try withTimeZone("America/Los_Angeles") {
                let loaded = try repository.load()
                XCTAssertEqual(loaded, original)
                XCTAssertEqual(dayString(original.entries[0].date), "2026-10-01")
                XCTAssertEqual(dayString(loaded.entries[0].date), "2026-10-01")
                XCTAssertEqual(dayString(loaded.weights[0].date), "2026-10-01")
                XCTAssertEqual(Calendar.current.component(.hour, from: loaded.entries[0].date), 0)
                let octoberFirst = date("2026-10-01T19:00:00Z")
                XCTAssertEqual(NutritionAnalytics.entries(on: octoberFirst, in: loaded.entries).count, 1)
                XCTAssertTrue(NutritionAnalytics.entries(on: date("2026-09-30T19:00:00Z"), in: loaded.entries).isEmpty)
                let summaries = NutritionAnalytics.dailySummaries(ending: octoberFirst, days: 2, entries: loaded.entries)
                XCTAssertEqual(summaries.map(\.isRecorded), [false, true])
                XCTAssertEqual(summaries.map(\.nutrition.energy), [0, 200])
            }
        }
    }

    func testDateSetterChangesChosenDayAndKeepsItInAnotherZone() throws {
        var entry = withTimeZone("Asia/Tokyo") { MealEntry(date: date("2026-10-01T03:00:00Z"), foodName: "食品") }
        var weight = withTimeZone("Asia/Tokyo") { WeightEntry(date: date("2026-10-01T03:00:00Z"), kilograms: 62) }
        let originalID = entry.id
        withTimeZone("America/Los_Angeles") {
            let newDay = date("2026-11-03T23:45:00Z")
            entry.date = newDay
            weight.date = newDay
            XCTAssertEqual(dayString(entry.date), "2026-11-03")
        }
        try withTimeZone("Pacific/Honolulu") {
            XCTAssertEqual(dayString(entry.date), "2026-11-03")
            XCTAssertEqual(dayString(weight.date), "2026-11-03")
            XCTAssertEqual(entry.id, originalID)
            try Validation.validate(AppData(entries: [entry], weights: [weight]))
        }
    }

    func testLegacyAbsoluteDatesMigrateOnceUsingCurrentZone() throws {
        try withRepository { repository in
            try withTimeZone("Asia/Tokyo") {
                let legacyDate = date("2026-09-30T15:10:00Z")
                let data = AppData(entries: [MealEntry(date: legacyDate, foodName: "旧形式の記録")],
                                   weights: [WeightEntry(date: legacyDate, kilograms: 61.2)])
                var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(data)) as? [String: Any])
                for key in ["entries", "weights"] {
                    var records = try XCTUnwrap(json[key] as? [[String: Any]])
                    records[0].removeValue(forKey: "day")
                    records[0]["date"] = legacyDate.timeIntervalSinceReferenceDate
                    json[key] = records
                }
                let legacyBytes = try JSONSerialization.data(withJSONObject: json)
                try FileManager.default.createDirectory(at: repository.directory, withIntermediateDirectories: true)
                try legacyBytes.write(to: repository.fileURL)
                let migrated = try repository.load()
                XCTAssertEqual(dayString(migrated.entries[0].date), "2026-10-01")
                XCTAssertEqual(dayString(migrated.weights[0].date), "2026-10-01")
                try repository.save(migrated)
                XCTAssertEqual(try Data(contentsOf: repository.backupURL), legacyBytes)
                let savedJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: repository.fileURL)) as? [String: Any])
                for key in ["entries", "weights"] {
                    let record = try XCTUnwrap((savedJSON[key] as? [[String: Any]])?.first)
                    XCTAssertEqual(record["day"] as? String, "2026-10-01")
                    XCTAssertNil(record["date"])
                }
            }
            try withTimeZone("America/Los_Angeles") {
                let reloaded = try repository.load()
                XCTAssertEqual(dayString(reloaded.entries[0].date), "2026-10-01")
                XCTAssertEqual(dayString(reloaded.weights[0].date), "2026-10-01")
            }
        }
    }

    func testMalformedDayNeverFallsBackToLegacyDateAndRemainsProtected() throws {
        let data = AppData(entries: [MealEntry(foodName: "食品")], weights: [WeightEntry(kilograms: 60)])
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(data)) as? [String: Any])
        let malformed: [Any] = ["2026-02-30", "2025-02-29", "2026-13-01", "2026-01-00", "0000-01-01", "10000-01-01", "2026-1-01", "", NSNull(), 20261001]
        for key in ["entries", "weights"] {
            for badDay in malformed {
                var json = original
                var records = try XCTUnwrap(json[key] as? [[String: Any]])
                records[0]["day"] = badDay
                records[0]["date"] = date("2026-10-01T00:00:00Z").timeIntervalSinceReferenceDate
                json[key] = records
                let invalidBytes = try JSONSerialization.data(withJSONObject: json)
                XCTAssertThrowsError(try JSONDecoder().decode(AppData.self, from: invalidBytes))
            }
        }
        try withRepository { repository in
            var json = original
            var records = try XCTUnwrap(json["entries"] as? [[String: Any]])
            records[0]["day"] = "2026-02-30"
            json["entries"] = records
            let invalidBytes = try JSONSerialization.data(withJSONObject: json)
            try FileManager.default.createDirectory(at: repository.directory, withIntermediateDirectories: true)
            try invalidBytes.write(to: repository.fileURL)
            XCTAssertThrowsError(try repository.load())
            XCTAssertThrowsError(try repository.save(AppData()))
            XCTAssertEqual(try Data(contentsOf: repository.fileURL), invalidBytes)
        }
    }

    func testNonFiniteAndOutOfRangeInputDatesAreRejectedWithoutCalendarConversion() throws {
        for seconds in [Double.nan, .infinity, -.infinity, .greatestFiniteMagnitude, -Double.greatestFiniteMagnitude, 253_402_387_200, -62_135_683_201] {
            let invalid = Date(timeIntervalSince1970: seconds)
            let entry = MealEntry(date: invalid, foodName: "食品")
            let weight = WeightEntry(date: invalid, kilograms: 60)
            XCTAssertThrowsError(try Validation.validate(AppData(entries: [entry])))
            XCTAssertThrowsError(try Validation.validate(AppData(weights: [weight])))
            XCTAssertThrowsError(try JSONEncoder().encode(entry))
            XCTAssertThrowsError(try JSONEncoder().encode(weight))
        }
    }

    func testLeapDayAndDaylightSavingCivilDays() throws {
        try withTimeZone("America/Los_Angeles") {
            let first = MealEntry(date: date("2026-03-08T20:00:00Z"), foodName: "夏時間の開始日")
            let second = MealEntry(date: date("2026-03-09T20:00:00Z"), foodName: "翌日")
            XCTAssertEqual(second.date.timeIntervalSince(first.date), 23 * 3600)
            XCTAssertEqual(NutritionAnalytics.recordedDays(in: [first, second]), 2)
            let leapDay = MealEntry(date: date("2028-02-29T20:00:00Z"), foodName: "うるう日")
            let encoded = try JSONEncoder().encode(leapDay)
            try withTimeZone("Pacific/Auckland") {
                let decoded = try JSONDecoder().decode(MealEntry.self, from: encoded)
                XCTAssertEqual(dayString(decoded.date), "2028-02-29")
                try Validation.validate(AppData(entries: [decoded]))
            }
        }
    }
}
