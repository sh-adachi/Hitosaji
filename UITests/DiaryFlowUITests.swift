import XCTest

@MainActor
final class DiaryFlowUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--reset-data"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["きょう"].waitForExistence(timeout: 10))
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
    }

    func testPreviousDayMealRemainsSeparateFromTodayAfterRelaunch() {
        app.buttons["previousDay"].tap()
        XCTAssertTrue(app.buttons["returnToday"].waitForExistence(timeout: 5))
        assertSummary("0 kcal")

        let breakfast = app.buttons["add.breakfast"]
        reveal(breakfast)
        breakfast.tap()
        XCTAssertTrue(app.textFields["foodSearch"].waitForExistence(timeout: 5))
        replace(app.textFields["foodSearch"], with: "ゆで卵")
        dismissKeyboard()
        let egg = app.staticTexts["ゆで卵"].firstMatch
        reveal(egg)
        egg.tap()
        XCTAssertTrue(app.textFields["mealName"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["mealEnergy"].value as? String, "67")
        app.buttons["saveMeal"].tap()
        waitUntilMissing(app.buttons["saveMeal"])

        assertSummary("67 kcal")
        XCTAssertEqual(mealRows.count, 1)
        let yesterdayRecordID = mealRows.firstMatch.identifier
        let returnToday = app.buttons["returnToday"]
        reveal(returnToday)
        returnToday.tap()
        assertSummary("0 kcal")
        XCTAssertEqual(mealRows.count, 0, "A meal saved on the previous day must not appear in today's totals.")

        reveal(app.buttons["previousDay"])
        app.buttons["previousDay"].tap()
        assertSummary("67 kcal")
        XCTAssertEqual(mealRows.count, 1)
        XCTAssertEqual(mealRows.firstMatch.identifier, yesterdayRecordID)

        relaunchKeepingRecords()
        assertSummary("0 kcal")
        XCTAssertEqual(mealRows.count, 0, "A fresh launch opens today while preserving meals recorded on other days.")
        app.buttons["previousDay"].tap()
        assertSummary("67 kcal")
        XCTAssertEqual(mealRows.count, 1)
        XCTAssertEqual(mealRows.firstMatch.identifier, yesterdayRecordID)
    }

    func testEditingAndDeletingCustomFoodPreservesRecordedNutrition() {
        let foodName = "Snapshot Soup"
        app.tabBars.buttons["食品"].tap()
        app.buttons["addCustomFood"].tap()
        XCTAssertTrue(app.textFields["mealName"].waitForExistence(timeout: 5))
        replace(app.textFields["mealName"], with: foodName)
        replace(app.textFields["mealServing"], with: "1 bowl")
        replace(app.textFields["mealEnergy"], with: "200")
        replace(app.textFields["mealProtein"], with: "10")
        replace(app.textFields["mealFat"], with: "8")
        replace(app.textFields["mealCarbs"], with: "22")
        dismissKeyboard()
        app.buttons["saveFood"].tap()
        waitUntilMissing(app.buttons["saveFood"])

        let customFilter = app.segmentedControls.buttons["マイ食品"]
        reveal(customFilter)
        customFilter.tap()
        let food = customFood(named: foodName)
        XCTAssertTrue(food.waitForExistence(timeout: 5))
        XCTAssertTrue(food.label.contains("200キロカロリー"))
        reveal(food)
        food.tap()
        XCTAssertTrue(app.textFields["mealName"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["mealEnergy"].value as? String, "200")
        app.buttons["saveMeal"].tap()
        waitUntilMissing(app.buttons["saveMeal"])

        app.tabBars.buttons["きょう"].tap()
        assertSummary("200 kcal")
        XCTAssertEqual(mealRows.count, 1)
        let originalMealID = mealRows.firstMatch.identifier

        app.tabBars.buttons["食品"].tap()
        let menu = app.buttons["\(foodName)の操作"]
        reveal(menu)
        menu.tap()
        app.buttons["食品を編集"].tap()
        XCTAssertTrue(app.textFields["mealName"].waitForExistence(timeout: 5))
        replace(app.textFields["mealEnergy"], with: "340")
        replace(app.textFields["mealProtein"], with: "20")
        replace(app.textFields["mealFat"], with: "12")
        replace(app.textFields["mealCarbs"], with: "38")
        dismissKeyboard()
        app.buttons["saveFood"].tap()
        waitUntilMissing(app.buttons["saveFood"])
        XCTAssertTrue(food.label.contains("340キロカロリー"), "The saved food itself should reflect its edited nutrition.")

        app.tabBars.buttons["きょう"].tap()
        assertSummary("200 kcal")
        XCTAssertEqual(mealRows.count, 1)
        XCTAssertEqual(mealRows.firstMatch.identifier, originalMealID)
        reveal(mealRows.firstMatch)
        mealRows.firstMatch.tap()
        XCTAssertTrue(app.textFields["mealName"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["mealEnergy"].value as? String, "200")
        XCTAssertEqual(app.textFields["mealProtein"].value as? String, "10")
        XCTAssertEqual(app.textFields["mealFat"].value as? String, "8")
        XCTAssertEqual(app.textFields["mealCarbs"].value as? String, "22", "Recorded meals keep the nutrition snapshot from the time they were saved.")
        app.buttons["キャンセル"].tap()
        waitUntilMissing(app.buttons["saveMeal"])

        app.tabBars.buttons["食品"].tap()
        reveal(menu)
        menu.tap()
        app.buttons["マイ食品を削除"].tap()
        XCTAssertTrue(app.staticTexts["これまでの食事記録はそのまま残ります。"].waitForExistence(timeout: 5))
        app.buttons["マイ食品を削除"].tap()
        waitUntilMissing(food)

        app.tabBars.buttons["きょう"].tap()
        assertSummary("200 kcal")
        XCTAssertEqual(mealRows.count, 1)
        XCTAssertEqual(mealRows.firstMatch.identifier, originalMealID)
        relaunchKeepingRecords()
        assertSummary("200 kcal")
        XCTAssertEqual(mealRows.firstMatch.identifier, originalMealID)
        app.tabBars.buttons["食品"].tap()
        app.segmentedControls.buttons["マイ食品"].tap()
        XCTAssertFalse(customFood(named: foodName).exists, "The food deletion and the retained meal snapshot must both persist.")
    }

    private var mealRows: XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "meal."))
    }

    private func customFood(named name: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name + "、")).firstMatch
    }

    private func relaunchKeepingRecords() {
        app.terminate()
        app.launchArguments = ["--uitesting"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["きょう"].waitForExistence(timeout: 10))
    }

    private func assertSummary(_ expected: String, file: StaticString = #filePath, line: UInt = #line) {
        let energy = app.descendants(matching: .any)["energyTotal"].firstMatch
        reveal(energy, preferDown: true, file: file, line: line)
        XCTAssertEqual(energy.value as? String, expected, file: file, line: line)
    }

    private func replace(_ field: XCUIElement, with text: String) {
        dismissKeyboard()
        reveal(field)
        field.tap()
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
        let previous = field.value as? String ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: previous.count) + text)
    }

    private func dismissKeyboard() {
        if app.keyboards.firstMatch.exists {
            let done = app.buttons["完了"].firstMatch
            if done.exists && done.isHittable { done.tap() }
        }
    }

    private func waitUntilMissing(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 5), .completed, file: file, line: line)
    }

    private func reveal(_ element: XCUIElement, preferDown: Bool = false, file: StaticString = #filePath, line: UInt = #line) {
        dismissKeyboard()
        for _ in 0..<12 {
            let exists = element.exists
            let frame = exists ? element.frame : .zero
            let screen = app.frame
            let top = screen.minY + 110
            let bottom = screen.maxY - 110
            if exists && element.isHittable && frame.midY > top && frame.midY < bottom { return }
            if exists && frame != .zero {
                if frame.midY <= top { app.swipeDown() }
                else { app.swipeUp() }
            } else if preferDown {
                app.swipeDown()
            } else {
                app.swipeUp()
            }
        }
        XCTFail("Could not reveal UI element safely: \(element)", file: file, line: line)
    }
}
