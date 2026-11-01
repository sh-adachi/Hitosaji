import Foundation
import XCTest
@testable import NutritionCore

final class PhotoAnalysisTests: XCTestCase {
    private func sampleItem() -> PhotoAnalysisItem {
        PhotoAnalysisItem(name: "ごはん", serving: "茶碗1杯・約150g",
                          nutrition: Nutrition(energy: 234, protein: 3.8, fat: 0.5, carbs: 55.7, fiber: 2.3, salt: 0),
                          confidence: .medium, reason: "器の大きさから量を推定")
    }

    private func decode(_ result: PhotoAnalysisResult) throws -> PhotoAnalysisResult {
        try PhotoAnalysisResult.decodeValidated(JSONEncoder().encode(result))
    }

    func testMultipleFoodsDecodeWithoutIdentifiersAndKeepIndependentNutrition() throws {
        let second = PhotoAnalysisItem(name: "焼き魚", serving: "1切れ・約80g",
                                       nutrition: Nutrition(energy: 160, protein: 18, fat: 9, carbs: 0.2, fiber: 0, salt: 1.2),
                                       confidence: .low, reason: "魚の種類と調味料は写真だけでは不明")
        let original = PhotoAnalysisResult(items: [sampleItem(), second], note: "器や隠れた食材により誤差があります。")
        let encoded = try JSONEncoder().encode(original)
        let result = try PhotoAnalysisResult.decodeValidated(encoded)
        XCTAssertEqual(result, original)
        XCTAssertEqual(result.items.map(\.nutrition.energy), [234, 160])
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let items = try XCTUnwrap(json["items"] as? [[String: Any]])
        XCTAssertTrue(items.allSatisfy { $0["id"] == nil })
        XCTAssertEqual(items[0]["confidence"] as? String, "medium")
    }

    func testOptionalUnknownNutrientsAreNotTurnedIntoZero() throws {
        let json = """
        {"items":[
          {"name":"スープ","serving":"1杯","nutrition":{"energy":40,"protein":2,"fat":1,"carbs":6,"fiber":null,"salt":null},"confidence":"low","reason":"具と塩分が不明"},
          {"name":"パン","serving":"1枚","nutrition":{"energy":150,"protein":5,"fat":3,"carbs":27},"confidence":"high","reason":""}
        ],"note":""}
        """
        let result = try PhotoAnalysisResult.decodeValidated(Data(json.utf8))
        XCTAssertTrue(result.items.allSatisfy { $0.nutrition.fiber == nil && $0.nutrition.salt == nil })
        let entries = try result.mealEntries(date: Date(), period: .lunch)
        let total = NutritionAnalytics.total(entries)
        XCTAssertEqual(total.energy, 190)
        XCTAssertNil(total.fiber)
        XCTAssertNil(total.salt)
    }

    func testMalformedJSONMissingFieldsAndUnknownConfidenceAreRejected() throws {
        let malformed = [
            "{broken", "[]", "null", "{\"items\":[]}", "{\"note\":\"\"}",
            "{\"items\":[{\"name\":\"食品\"}],\"note\":\"\"}"
        ]
        for text in malformed {
            XCTAssertThrowsError(try PhotoAnalysisResult.decodeValidated(Data(text.utf8))) { error in
                XCTAssertEqual(error as? PhotoAnalysisError, .invalidResponse)
            }
        }
        let encoded = try JSONEncoder().encode(PhotoAnalysisResult(items: [sampleItem()]))
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        for replacement in ["certain", "HIGH", ""] {
            var json = original
            var items = try XCTUnwrap(json["items"] as? [[String: Any]])
            items[0]["confidence"] = replacement
            json["items"] = items
            XCTAssertThrowsError(try PhotoAnalysisResult.decodeValidated(JSONSerialization.data(withJSONObject: json)))
        }
        var json = original
        var items = try XCTUnwrap(json["items"] as? [[String: Any]])
        var nutrition = try XCTUnwrap(items[0]["nutrition"] as? [String: Any])
        nutrition["energy"] = "234"
        items[0]["nutrition"] = nutrition
        json["items"] = items
        XCTAssertThrowsError(try PhotoAnalysisResult.decodeValidated(JSONSerialization.data(withJSONObject: json)))
    }

    func testInvalidNutrientsAreRejectedAtDecodeAndBeforeMapping() throws {
        let fields: [(WritableKeyPath<Nutrition, Double>, Double)] = [
            (\.energy, 20_000), (\.protein, 2_000), (\.fat, 2_000), (\.carbs, 2_000)
        ]
        for (field, maximum) in fields {
            for invalid in [-1, maximum + 1] {
                var item = sampleItem()
                item.nutrition[keyPath: field] = invalid
                XCTAssertThrowsError(try decode(PhotoAnalysisResult(items: [item])))
            }
            for invalid in [Double.nan, .infinity, -.infinity] {
                var item = sampleItem()
                item.nutrition[keyPath: field] = invalid
                XCTAssertThrowsError(try PhotoAnalysisResult(items: [item]).mealEntries(date: Date(), period: .snack))
            }
        }
        let optionalFields: [(WritableKeyPath<Nutrition, Double?>, Double)] = [(\.fiber, 2_000), (\.salt, 200)]
        for (field, maximum) in optionalFields {
            for invalid in [-1, maximum + 1] {
                var item = sampleItem()
                item.nutrition[keyPath: field] = invalid
                XCTAssertThrowsError(try decode(PhotoAnalysisResult(items: [item])))
            }
            var item = sampleItem()
            item.nutrition[keyPath: field] = .nan
            XCTAssertThrowsError(try PhotoAnalysisResult(items: [item]).mealEntries(date: Date(), period: .snack))
        }
    }

    func testCountAndTextBoundariesAreInclusiveAndValidated() throws {
        var item = sampleItem()
        item.name = String(repeating: "食", count: 200)
        item.serving = String(repeating: "量", count: 200)
        item.reason = String(repeating: "理", count: 500)
        item.nutrition = Nutrition(energy: 20_000, protein: 2_000, fat: 2_000, carbs: 2_000, fiber: 2_000, salt: 200)
        let atLimit = PhotoAnalysisResult(items: Array(repeating: item, count: 12), note: String(repeating: "注", count: 1_000))
        XCTAssertNoThrow(try decode(atLimit))
        XCTAssertTrue(try atLimit.mealEntries(date: Date(), period: .dinner).allSatisfy { $0.note.count <= 2_000 })

        var tooMany = atLimit
        tooMany.items.append(item)
        XCTAssertThrowsError(try decode(tooMany)) { error in
            XCTAssertEqual(error as? PhotoAnalysisError, .tooManyItems)
        }
        var longNote = atLimit
        longNote.note.append("注")
        XCTAssertThrowsError(try decode(longNote))
        for field in [\PhotoAnalysisItem.name, \.serving, \.reason] {
            var tooLong = item
            tooLong[keyPath: field].append("字")
            XCTAssertThrowsError(try decode(PhotoAnalysisResult(items: [tooLong])))
        }
        for blank in ["", " \t\n "] {
            var invalidName = sampleItem()
            invalidName.name = blank
            XCTAssertThrowsError(try decode(PhotoAnalysisResult(items: [invalidName])))
            var invalidServing = sampleItem()
            invalidServing.serving = blank
            XCTAssertThrowsError(try decode(PhotoAnalysisResult(items: [invalidServing])))
        }
    }

    func testMappingUsesSelectedDiaryDayOnePortionAndTraceableNote() throws {
        let chosenDate = ISO8601DateFormatter().date(from: "2026-10-11T15:15:00Z")!
        let item = sampleItem()
        let result = PhotoAnalysisResult(items: [item, item], note: "見えない油は推定です。")
        let entries = try result.mealEntries(date: chosenDate, period: .dinner)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(Set(entries.map(\.id)).count, 2)
        for entry in entries {
            XCTAssertTrue(Calendar.current.isDate(entry.date, inSameDayAs: chosenDate))
            XCTAssertEqual(entry.period, .dinner)
            XCTAssertEqual(entry.foodName, item.name)
            XCTAssertEqual(entry.serving, item.serving)
            XCTAssertEqual(entry.portions, 1)
            XCTAssertEqual(entry.total, item.nutrition)
            XCTAssertTrue(entry.note.contains("AI推定"))
            XCTAssertTrue(entry.note.contains("確かさ：中"))
            XCTAssertTrue(entry.note.contains(item.reason))
            XCTAssertTrue(entry.note.contains(result.note))
        }
        XCTAssertEqual(result.items, [item, item])
        XCTAssertThrowsError(try result.mealEntries(date: Date(timeIntervalSince1970: .nan), period: .lunch))
    }

    func testEditedResultIsRevalidatedAndOptionalExplanationsCanBeEmpty() throws {
        var item = sampleItem()
        item.reason = " \n "
        var result = try decode(PhotoAnalysisResult(items: [item], note: ""))
        let entries = try result.mealEntries(date: Date(), period: .breakfast)
        XCTAssertEqual(entries[0].note, "AI推定（確かさ：中）")
        result.items[0].serving = " "
        XCTAssertThrowsError(try result.mealEntries(date: Date(), period: .breakfast))
    }

    func testNoRecognizedFoodIsAValidEmptyResult() throws {
        let result = try PhotoAnalysisResult.decodeValidated(Data("{\"items\":[],\"note\":\"食品を特定できませんでした。\"}".utf8))
        XCTAssertTrue(result.items.isEmpty)
        XCTAssertTrue(try result.mealEntries(date: Date(), period: .lunch).isEmpty)
        XCTAssertEqual(result.note, "食品を特定できませんでした。")
    }
}
