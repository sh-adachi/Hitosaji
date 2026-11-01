import XCTest

@MainActor
final class PhotoAnalysisUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDownWithError() throws { app?.terminate(); app = nil }

    func testReviewEditBatchSaveAndPersist() {
        launch()
        openPhoto()
        analyzeFixture()
        XCTAssertTrue(app.buttons["photoSave"].waitForExistence(timeout: 5))
        capture("Photo-Review")
        let edit = app.buttons["photoEdit_0"]
        reveal(edit); edit.tap()
        replace(app.textFields["photoName_0"], with: "修正したごはん")
        replace(app.textFields["photoEnergy_0"], with: "250")
        let fiber = app.textFields["photoFiber_0"]
        reveal(fiber)
        XCTAssertEqual(fiber.value as? String, "不明")
        dismissKeyboard()
        app.buttons["photoSave"].tap()
        XCTAssertTrue(app.buttons["photoSave"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["きょう"].waitForExistence(timeout: 5))
        XCTAssertEqual(mealRows.count, 2)
        assertEnergy("430 kcal")
        app.terminate(); app.launchArguments = ["--uitesting"]; app.launch()
        XCTAssertTrue(app.tabBars.buttons["きょう"].waitForExistence(timeout: 10))
        assertEnergy("430 kcal")
        XCTAssertEqual(mealRows.count, 2)
        let rice = mealRows.matching(NSPredicate(format: "label CONTAINS %@", "修正したごはん")).firstMatch
        reveal(rice); rice.tap()
        XCTAssertEqual(app.textFields["mealName"].value as? String, "修正したごはん")
        let note = app.textFields["mealNote"]
        reveal(note)
        XCTAssertTrue((note.value as? String ?? "").contains("AI推定"))
    }

    func testExcludeDishAndSaveOnlySelected() {
        launch(); openPhoto(); analyzeFixture()
        let included = app.switches["photoInclude_1"]
        reveal(included); included.tap()
        XCTAssertEqual(included.value as? String, "0")
        app.buttons["photoSave"].tap()
        XCTAssertTrue(app.buttons["photoSave"].waitForNonExistence(timeout: 5))
        XCTAssertEqual(mealRows.count, 1)
        assertEnergy("234 kcal")
    }

    func testNoFoodDoesNotCreateRecords() {
        launch(extra: ["--photo-fixture-empty"]); openPhoto(); analyzeFixture()
        XCTAssertTrue(app.descendants(matching: .any)["photoEmpty"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["photoSave"].exists && app.buttons["photoSave"].isEnabled)
        cancelToDiary()
        XCTAssertEqual(mealRows.count, 0); assertEnergy("0 kcal")
    }

    func testFailureAllowsRetryAndCancelWithoutSaving() {
        launch(extra: ["--photo-fixture-error"]); openPhoto(); analyzeFixture()
        let error = app.descendants(matching: .any)["photoError"].firstMatch
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        let retry = app.buttons["photoAnalyze"]
        reveal(retry); XCTAssertTrue(retry.isEnabled); retry.tap()
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        capture("Photo-Retry")
        cancelToDiary()
        XCTAssertEqual(mealRows.count, 0); assertEnergy("0 kcal")
    }

    func testCancelReviewDoesNotSave() {
        launch(); openPhoto(); analyzeFixture()
        XCTAssertTrue(app.buttons["photoSave"].waitForExistence(timeout: 5))
        cancelToDiary()
        XCTAssertEqual(mealRows.count, 0); assertEnergy("0 kcal")
    }

    private var mealRows: XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "meal."))
    }

    private func launch(extra: [String] = []) {
        app.launchArguments = ["--uitesting", "--reset-data", "--photo-fixture"] + extra
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["きょう"].waitForExistence(timeout: 10))
    }

    private func openPhoto() {
        let add = app.buttons["add.breakfast"]
        reveal(add); add.tap()
        let photo = app.buttons["photoEntry"]
        XCTAssertTrue(photo.waitForExistence(timeout: 5)); reveal(photo); photo.tap()
        XCTAssertTrue(app.buttons["photoFixtureImage"].waitForExistence(timeout: 5))
    }

    private func analyzeFixture() {
        let fixture = app.buttons["photoFixtureImage"]
        reveal(fixture); fixture.tap()
        let analyze = app.buttons["photoAnalyze"]
        reveal(analyze); XCTAssertTrue(analyze.isEnabled); analyze.tap()
    }

    private func cancelToDiary() {
        app.buttons["photoCancel"].tap()
        XCTAssertTrue(app.buttons["photoEntry"].waitForExistence(timeout: 5))
        app.buttons["キャンセル"].tap()
        XCTAssertTrue(app.tabBars.buttons["きょう"].waitForExistence(timeout: 5))
    }

    private func assertEnergy(_ expected: String) {
        let total = app.descendants(matching: .any)["energyTotal"].firstMatch
        reveal(total)
        XCTAssertEqual(total.value as? String, expected)
    }

    private func replace(_ field: XCUIElement, with text: String) {
        dismissKeyboard(); reveal(field); field.tap()
        let old = field.value as? String ?? ""
        if !old.isEmpty && old != field.placeholderValue {
            field.press(forDuration: 1.2)
            let predicate = NSPredicate(format: "label IN %@", ["すべてを選択", "すべて選択", "Select All"])
            let menu = app.menuItems.matching(predicate).firstMatch
            let button = app.buttons.matching(predicate).firstMatch
            if menu.waitForExistence(timeout: 2) { menu.tap() }
            else if button.exists { button.tap() }
            field.typeText(XCUIKeyboardKey.delete.rawValue)
        }
        field.typeText(text)
        XCTAssertEqual(field.value as? String, text)
        dismissKeyboard()
    }

    private func dismissKeyboard() {
        if app.keyboards.firstMatch.exists {
            let done = app.buttons["完了"].firstMatch
            if done.isHittable { done.tap() }
        }
    }

    private func reveal(_ element: XCUIElement) {
        dismissKeyboard()
        for _ in 0..<12 {
            if element.exists && element.isHittable && element.frame.midY > 120 && element.frame.midY < app.frame.maxY - 70 { return }
            if element.exists && element.frame.midY < 120 { app.swipeDown() }
            else { app.swipeUp() }
        }
        XCTFail("Element not reachable: \(element)\n\(app.debugDescription)")
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
