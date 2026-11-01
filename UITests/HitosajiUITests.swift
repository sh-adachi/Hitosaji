import XCTest

@MainActor
final class HitosajiUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
    }

    func testCatalogPortionsPersistEditWithoutDuplicateAndDelete() {
        launchFresh()
        openBreakfast()
        replace(app.textFields["foodSearch"], with: "ごはん")
        dismissKeyboard()
        let rice = app.staticTexts["ごはん"].firstMatch
        reveal(rice)
        rice.tap()

        XCTAssertEqual(app.textFields["mealEnergy"].value as? String, "234")
        replace(app.textFields["mealPortions"], with: "0.5")
        saveMeal()
        assertEnergy("117 kcal")
        XCTAssertEqual(mealRows.count, 1)
        assertMealRowContains("茶碗1杯・150g × 0.5", energy: "117")

        relaunchKeepingRecords()
        assertEnergy("117 kcal")
        XCTAssertEqual(mealRows.count, 1)
        reveal(mealRows.firstMatch)
        mealRows.firstMatch.tap()
        XCTAssertTrue(app.textFields["mealName"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["mealName"].value as? String, "ごはん")
        replace(app.textFields["mealPortions"], with: "1.5")
        saveMeal()
        assertEnergy("351 kcal")
        XCTAssertEqual(mealRows.count, 1, "Editing must update the original entry instead of inserting another meal.")
        assertMealRowContains("茶碗1杯・150g × 1.5", energy: "351")

        mealRows.firstMatch.tap()
        XCTAssertTrue(app.textFields["mealName"].waitForExistence(timeout: 5))
        replace(app.textFields["mealPortions"], with: "0.25")
        saveMeal()
        assertEnergy("58.5 kcal")
        assertMealRowContains("茶碗1杯・150g × 0.25", energy: "58.5")
        mealRows.firstMatch.tap()
        XCTAssertTrue(app.textFields["mealName"].waitForExistence(timeout: 5))
        let delete = app.buttons["この記録を削除"]
        reveal(delete)
        delete.tap()
        let confirmedDelete = app.buttons["記録を削除"]
        XCTAssertTrue(confirmedDelete.waitForExistence(timeout: 5))
        confirmedDelete.tap()
        XCTAssertTrue(app.tabBars.buttons["きょう"].waitForExistence(timeout: 5))
        assertEnergy("0 kcal")
        XCTAssertEqual(mealRows.count, 0)
        relaunchKeepingRecords()
        assertEnergy("0 kcal")
        XCTAssertEqual(mealRows.count, 0, "Deleted records must remain deleted after relaunch.")
    }

    func testManualMealRequiresNutritionPreservesUnknownValuesAndSavesFood() {
        launchFresh()
        openBreakfast()
        app.buttons["manualEntry"].tap()
        replace(app.textFields["mealName"], with: "テストのスープ")
        dismissKeyboard()
        app.buttons["saveMeal"].tap()
        let validationAlert = app.alerts["入力を確認してください"]
        XCTAssertTrue(validationAlert.waitForExistence(timeout: 5))
        XCTAssertTrue(validationAlert.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "カロリーを入力")).firstMatch.exists)
        validationAlert.buttons["OK"].tap()

        replace(app.textFields["mealServing"], with: "1 杯・200 ml")
        replace(app.textFields["mealEnergy"], with: "120")
        replace(app.textFields["mealProtein"], with: "8")
        replace(app.textFields["mealFat"], with: "4")
        replace(app.textFields["mealCarbs"], with: "13")
        dismissKeyboard()
        let saveAsFood = app.switches["マイ食品にも保存"]
        reveal(saveAsFood)
        saveAsFood.tap()
        XCTAssertEqual(saveAsFood.value as? String, "1")
        saveMeal()
        assertEnergy("120 kcal")
        XCTAssertEqual(mealRows.count, 1)

        let detail = app.buttons["nutritionDetail"]
        reveal(detail)
        detail.tap()
        let unknowns = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "未入力あり"))
        XCTAssertGreaterThanOrEqual(unknowns.count, 2, "Unknown fiber and salt must not be silently recorded as zero.")
        app.buttons["閉じる"].tap()

        assertSavedCustomSoup()
        relaunchKeepingRecords()
        assertEnergy("120 kcal")
        XCTAssertEqual(mealRows.count, 1)
        assertSavedCustomSoup()

        let soup = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "テストのスープ、")).firstMatch
        soup.tap()
        XCTAssertEqual(app.textFields["mealEnergy"].value as? String, "120")
        XCTAssertEqual(app.textFields["mealProtein"].value as? String, "8")
        let fiber = app.textFields["mealFiber"]
        reveal(fiber)
        XCTAssertEqual(fiber.value as? String, "不明")
        XCTAssertEqual(app.textFields["mealSalt"].value as? String, "不明")
        app.buttons["キャンセル"].tap()
        app.tabBars.buttons["きょう"].tap()
        XCTAssertEqual(mealRows.count, 1, "Cancelling a food selection must not record a second meal.")
    }

    func testGoalsAndWeightPersistAndCancelDoesNotMutate() {
        launchFresh()
        app.tabBars.buttons["設定"].tap()
        app.buttons["editGoals"].tap()
        replace(app.textFields["goalEnergy"], with: "2100")
        replace(app.textFields["goalProtein"], with: "90")
        dismissKeyboard()
        app.buttons["saveGoals"].tap()
        XCTAssertTrue(app.buttons["editGoals"].waitForExistence(timeout: 5))
        app.buttons["editGoals"].tap()
        XCTAssertEqual(app.textFields["goalEnergy"].value as? String, "2100")
        replace(app.textFields["goalEnergy"], with: "2300")
        dismissKeyboard()
        app.buttons["キャンセル"].tap()

        app.tabBars.buttons["ふりかえり"].tap()
        let addWeight = app.buttons["addWeight"]
        reveal(addWeight)
        addWeight.tap()
        replace(app.textFields["weightValue"], with: "62.4")
        dismissKeyboard()
        app.buttons["saveWeight"].tap()
        XCTAssertTrue(app.tabBars.buttons["ふりかえり"].waitForExistence(timeout: 5))
        XCTAssertEqual(weightRows.count, 1)

        relaunchKeepingRecords()
        app.tabBars.buttons["設定"].tap()
        app.buttons["editGoals"].tap()
        XCTAssertEqual(app.textFields["goalEnergy"].value as? String, "2100", "Cancelled edits must not replace the saved goal.")
        XCTAssertEqual(app.textFields["goalProtein"].value as? String, "90")
        app.buttons["キャンセル"].tap()
        app.tabBars.buttons["ふりかえり"].tap()
        XCTAssertEqual(weightRows.count, 1)
        reveal(weightRows.firstMatch)
        weightRows.firstMatch.tap()
        XCTAssertEqual(app.textFields["weightValue"].value as? String, "62.4")
        replace(app.textFields["weightValue"], with: "65")
        dismissKeyboard()
        app.buttons["キャンセル"].tap()
        weightRows.firstMatch.tap()
        XCTAssertEqual(app.textFields["weightValue"].value as? String, "62.4", "Cancelling a weight edit must preserve the existing value.")
        app.buttons["キャンセル"].tap()
        XCTAssertEqual(weightRows.count, 1)
    }

    func testScreenshotTourWithFictionalSampleData() {
        launchFresh(sample: true)
        XCTAssertTrue(app.descendants(matching: .any)["energyTotal"].waitForExistence(timeout: 5))
        capture("01-Today")

        app.tabBars.buttons["食品"].tap()
        XCTAssertTrue(app.textFields["libraryFoodSearch"].waitForExistence(timeout: 5))
        capture("02-Food-Library")

        app.tabBars.buttons["ふりかえり"].tap()
        XCTAssertTrue(app.buttons["addWeight"].waitForExistence(timeout: 5))
        capture("03-Trends")

        app.tabBars.buttons["きょう"].tap()
        openBreakfast()
        replace(app.textFields["foodSearch"], with: "ヨーグルト")
        dismissKeyboard()
        let yogurt = app.staticTexts["プレーンヨーグルト"].firstMatch
        reveal(yogurt)
        yogurt.tap()
        XCTAssertTrue(app.textFields["mealName"].waitForExistence(timeout: 5))
        capture("04-Meal-Editor")
        app.buttons["キャンセル"].tap()
    }

    private var mealRows: XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "meal."))
    }

    private var weightRows: XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "weight."))
    }

    private func launchFresh(sample: Bool = false) {
        app.launchArguments = ["--uitesting", "--reset-data"] + (sample ? ["--sample-data"] : [])
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["きょう"].waitForExistence(timeout: 10))
    }

    private func relaunchKeepingRecords() {
        app.terminate()
        app.launchArguments = ["--uitesting"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["きょう"].waitForExistence(timeout: 10))
    }

    private func openBreakfast() {
        let add = app.buttons["add.breakfast"]
        reveal(add)
        add.tap()
        XCTAssertTrue(app.textFields["foodSearch"].waitForExistence(timeout: 5))
    }

    private func saveMeal() {
        dismissKeyboard()
        app.buttons["saveMeal"].tap()
        XCTAssertTrue(app.tabBars.buttons["きょう"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["saveMeal"].waitForNonExistence(timeout: 5), app.debugDescription)
    }

    private func assertEnergy(_ expected: String, file: StaticString = #filePath, line: UInt = #line) {
        dismissKeyboard()
        let energy = app.descendants(matching: .any)["energyTotal"].firstMatch
        for _ in 0..<10 {
            if energy.isHittable { break }
            app.swipeDown()
        }
        XCTAssertTrue(energy.waitForExistence(timeout: 5), file: file, line: line)
        XCTAssertEqual(energy.value as? String, expected, file: file, line: line)
    }

    private func assertMealRowContains(_ serving: String, energy: String, file: StaticString = #filePath, line: UInt = #line) {
        let row = mealRows.firstMatch
        reveal(row)
        let text = row.label + " " + row.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " ")
        XCTAssertTrue(text.contains(serving), "Missing serving '\(serving)' in: \(text)", file: file, line: line)
        XCTAssertTrue(text.contains(energy), "Missing energy '\(energy)' in: \(text)", file: file, line: line)
    }

    private func assertSavedCustomSoup() {
        app.tabBars.buttons["食品"].tap()
        XCTAssertTrue(app.textFields["libraryFoodSearch"].waitForExistence(timeout: 5))
        replace(app.textFields["libraryFoodSearch"], with: "テストのスープ")
        dismissKeyboard()
        app.segmentedControls.buttons["マイ食品"].tap()
        let soup = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "テストのスープ、")).firstMatch
        XCTAssertTrue(soup.waitForExistence(timeout: 5))
        XCTAssertTrue(soup.label.contains("120"))
    }

    private func replace(_ field: XCUIElement, with text: String) {
        dismissKeyboard()
        reveal(field)
        field.tap()
        let oldText = field.value as? String ?? ""
        if !oldText.isEmpty && (oldText != field.placeholderValue || field.identifier == "mealPortions") {
            field.press(forDuration: 1.2)
            let selectAll = app.menuItems.matching(NSPredicate(format: "label IN %@", ["すべてを選択", "すべて選択", "Select All"])).firstMatch
            let selectAllButton = app.buttons.matching(NSPredicate(format: "label IN %@", ["すべてを選択", "すべて選択", "Select All"])).firstMatch
            if selectAll.waitForExistence(timeout: 2) { selectAll.tap() }
            else if selectAllButton.exists { selectAllButton.tap() }
            field.typeText(XCUIKeyboardKey.delete.rawValue)
            let cleared = field.value as? String ?? ""
            XCTAssertTrue(cleared.isEmpty || cleared == field.placeholderValue, "Select-all must clear the previous value. Actual: \(cleared)\n\(app.debugDescription)")
        }
        field.typeText(text)
        XCTAssertEqual(field.value as? String, text, "The input must contain exactly the replacement value.")
    }

    private func dismissKeyboard() {
        if app.keyboards.firstMatch.exists {
            let done = app.buttons["完了"].firstMatch
            if done.exists && done.isHittable { done.tap() }
        }
    }

    private func reveal(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        dismissKeyboard()
        for _ in 0..<12 {
            let exists = element.exists
            let frame = exists ? element.frame : .zero
            let top = app.frame.minY + 110
            let editing = ["saveMeal", "saveFood", "saveGoals", "saveWeight"].contains { app.buttons[$0].exists }
            let bottom = app.frame.maxY - (editing ? 35 : 110)
            if exists && element.isHittable && frame.midY > top && frame.midY < bottom { return }
            if exists && frame != .zero && frame.midY <= top { app.swipeDown() }
            else { app.swipeUp() }
        }
        XCTFail("Could not reveal UI element safely: \(element)", file: file, line: line)
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
