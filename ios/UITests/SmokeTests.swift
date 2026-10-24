import XCTest

final class SmokeTests: XCTestCase {
    func testOfflineLaunchAndDraft() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["Собрать команды"].waitForExistence(timeout: 15))
        attach(app, name: "01-randomizer")
        app.buttons["Собрать команды"].tap()
        XCTAssertTrue(app.navigationBars["Состав команды"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["draft-player"].exists)
        attach(app, name: "02-drafted-team")
        app.buttons["draft-player"].tap()
        XCTAssertTrue(app.navigationBars["Карточка игрока"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.segmentedControls.buttons["Атрибуты"].waitForExistence(timeout: 10))
        attach(app, name: "03-player-details")
        app.buttons["Готово"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.tabBars.buttons["Игроки"].tap()
        XCTAssertTrue(app.navigationBars["Игроки"].waitForExistence(timeout: 10))
        attach(app, name: "04-roster")
    }

    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
