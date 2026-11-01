import Foundation
import XCTest
@testable import NutritionCore

final class RepositoryTests: XCTestCase {
    private func withRepository(_ body: (NutritionRepository) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("HitosajiTests-" + UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(NutritionRepository(directory: directory))
    }

    func testMissingDataIsEmptyAndSaveRoundTripsAllFields() throws {
        try withRepository { repository in
            XCTAssertEqual(try repository.load(), AppData())
            let date = Date(timeIntervalSince1970: 1_800_000_000)
            let food = Food(name: "マイ食品", serving: "100g", nutrition: Nutrition(energy: 80, protein: 10, fat: 3, carbs: 2), isCustom: true)
            let first = AppData(entries: [MealEntry(date: date, period: .lunch, foodName: food.name, serving: food.serving, portions: 1.5, nutrition: food.nutrition, note: "昼の記録")], weights: [WeightEntry(date: date, kilograms: 62.5)], customFoods: [food])
            try repository.save(first)
            XCTAssertEqual(try repository.load(), first)
            var second = first
            second.entries[0].portions = 2
            second.goals.isExample = false
            let originalBytes = try Data(contentsOf: repository.fileURL)
            try repository.save(second)
            XCTAssertEqual(try repository.load(), second)
            XCTAssertEqual(try Data(contentsOf: repository.backupURL), originalBytes)
            XCTAssertEqual(try repository.load().entries[0].total.energy, 160)
        }
    }

    func testCorruptedDataIsNeverSilentlyResetOrOverwritten() throws {
        try withRepository { repository in
            try FileManager.default.createDirectory(at: repository.directory, withIntermediateDirectories: true)
            let corrupt = Data("{broken json".utf8)
            try corrupt.write(to: repository.fileURL)
            XCTAssertThrowsError(try repository.load())
            XCTAssertThrowsError(try repository.save(AppData()))
            XCTAssertEqual(try Data(contentsOf: repository.fileURL), corrupt)
            XCTAssertFalse(FileManager.default.fileExists(atPath: repository.backupURL.path))
        }
    }

    func testUnknownSchemaIsProtectedOnLoadAndSave() throws {
        try withRepository { repository in
            try FileManager.default.createDirectory(at: repository.directory, withIntermediateDirectories: true)
            let futureData = try JSONEncoder().encode(AppData(schemaVersion: 2))
            try futureData.write(to: repository.fileURL)
            XCTAssertThrowsError(try repository.load()) { error in
                XCTAssertEqual(error as? NutritionDataError, .unsupportedSchema(2))
            }
            XCTAssertThrowsError(try repository.save(AppData()))
            XCTAssertEqual(try Data(contentsOf: repository.fileURL), futureData)
        }
    }

    func testInvalidDecodedValuesAreProtected() throws {
        try withRepository { repository in
            try FileManager.default.createDirectory(at: repository.directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .deferredToDate
            let invalid = try encoder.encode(AppData(weights: [WeightEntry(kilograms: -1)]))
            try invalid.write(to: repository.fileURL)
            XCTAssertThrowsError(try repository.load())
            XCTAssertThrowsError(try repository.save(AppData()))
            XCTAssertEqual(try Data(contentsOf: repository.fileURL), invalid)
        }
    }

    func testValidationFailureKeepsLastSavedData() throws {
        try withRepository { repository in
            let first = AppData(entries: [MealEntry(foodName: "食品")])
            try repository.save(first)
            var invalid = first
            invalid.entries[0].portions = 0
            XCTAssertThrowsError(try repository.save(invalid))
            XCTAssertEqual(try repository.load(), first)
        }
    }

    func testBackupFailureKeepsPrimaryDataUntouched() throws {
        try withRepository { repository in
            try repository.save(AppData())
            let bytes = try Data(contentsOf: repository.fileURL)
            try FileManager.default.createDirectory(at: repository.backupURL, withIntermediateDirectories: true)
            try Data("do not replace".utf8).write(to: repository.backupURL.appendingPathComponent("protected.txt"))
            XCTAssertThrowsError(try repository.save(AppData(entries: [MealEntry(foodName: "追加食品")])) )
            XCTAssertEqual(try Data(contentsOf: repository.fileURL), bytes)
        }
    }

    func testUnwritableStorageLocationThrows() throws {
        try withRepository { repository in
            try FileManager.default.createDirectory(at: repository.directory, withIntermediateDirectories: true)
            let blocker = repository.directory.appendingPathComponent("file-instead-of-directory")
            try Data("blocker".utf8).write(to: blocker)
            let blockedRepository = NutritionRepository(directory: blocker)
            XCTAssertThrowsError(try blockedRepository.save(AppData()))
            XCTAssertEqual(try String(contentsOf: blocker, encoding: .utf8), "blocker")
        }
    }
}
