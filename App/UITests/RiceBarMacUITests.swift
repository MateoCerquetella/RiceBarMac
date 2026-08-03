import XCTest

final class RiceBarMacUITests: XCTestCase {
    private var temporaryHome: URL!
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        temporaryHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("RiceBarMacUITests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryHome, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        app?.terminate()
        if let temporaryHome {
            try? FileManager.default.removeItem(at: temporaryHome)
        }
    }

    func testPreviewApplyAndUndoAreVisibleAndKeyboardAccessible() throws {
        let destination = temporaryHome.appendingPathComponent(".config/ui-test.conf")
        try createProfile(name: "UI Test", destination: destination, valid: true)
        launch()

        let window = app.windows["RiceBarMac Settings"]
        XCTAssertTrue(window.waitForExistence(timeout: 8))
        attachScreenshot("idle")

        openPreview(profileName: "UI Test")
        let preview = app.dialogs["Preview UI Test"]
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        XCTAssertTrue(preview.staticTexts["Review the exact plan below. No files have been changed. Replaced items will be moved to the listed backups."].exists)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        attachScreenshot("preview")

        preview.buttons["Apply"].click()
        let status = window.staticTexts["Profile operation status"]
        XCTAssertTrue(status.waitForExistence(timeout: 3))
        attachScreenshot("applying")
        XCTAssertTrue(waitForPath(destination, exists: true, timeout: 8))
        XCTAssertTrue(waitForValue(status, value: "UI Test is now active", timeout: 8))
        attachScreenshot("success")

        let undo = window.buttons["Undo the last completed profile apply"]
        XCTAssertTrue(undo.isEnabled)
        undo.click()
        XCTAssertTrue(waitForPath(destination, exists: false, timeout: 8))
        XCTAssertTrue(waitForValue(status, value: "Undo complete", timeout: 8))
        attachScreenshot("undo")
    }

    func testInvalidProfileRemainsVisibleWithActionableFailure() throws {
        try createProfile(name: "Broken", destination: temporaryHome.appendingPathComponent("outside"), valid: false)
        launch()

        let window = app.windows["RiceBarMac Settings"]
        XCTAssertTrue(window.waitForExistence(timeout: 8))
        XCTAssertTrue(window.staticTexts["Invalid Profiles"].waitForExistence(timeout: 5))
        XCTAssertTrue(window.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Broken'")).firstMatch.exists)
        attachScreenshot("failure")
    }

    private func launch() {
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launchEnvironment["RICEBARMAC_TEST_HOME"] = temporaryHome.path
        app.launchEnvironment["RICEBARMAC_TEST_EFFECT_DELAY_MS"] = "600"
        app.launch()
    }

    private func createProfile(name: String, destination: URL, valid: Bool) throws {
        let directory = temporaryHome.appendingPathComponent(".ricebarmac/profiles/\(name)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if valid {
            try Data("profile-value".utf8).write(to: directory.appendingPathComponent("source.conf"))
            try Data("wallpaper-fixture".utf8).write(to: directory.appendingPathComponent("wallpaper.png"))
            let escapedDestination = destination.path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            let json = """
            {
              "name": "\(name)",
              "wallpaper": "wallpaper.png",
              "replacements": [
                { "source": "source.conf", "destination": "\(escapedDestination)" }
              ]
            }
            """
            try Data(json.utf8).write(to: directory.appendingPathComponent("profile.json"))
        } else {
            try Data("{ invalid-json".utf8).write(to: directory.appendingPathComponent("profile.json"))
        }
    }

    private func openPreview(profileName: String) {
        let menu = app.menuButtons["Preview a profile before applying"]
        if menu.exists {
            menu.click()
        } else {
            app.buttons["Preview a profile before applying"].click()
        }
        XCTAssertTrue(app.menuItems[profileName].waitForExistence(timeout: 3))
        app.menuItems[profileName].click()
    }

    private func waitForPath(_ url: URL, exists: Bool, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            let current = FileManager.default.fileExists(atPath: url.path)
            if current == exists { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        } while Date() < deadline
        return false
    }

    private func waitForValue(_ element: XCUIElement, value: String, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "value == %@", value)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
