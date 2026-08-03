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

    func testPreviewApplyAndUndoAreVisibleAndAccessible() throws {
        let destination = temporaryHome.appendingPathComponent(".config/ui-test.conf")
        try createProfile(name: "UI Test", destination: destination, valid: true)
        launch()

        let window = app.windows["RiceBarMac Settings"]
        XCTAssertTrue(window.waitForExistence(timeout: 8))
        attachScreenshot("idle")

        openPreview()
        let status = window.descendants(matching: .any)["profile-operation-status"]
        XCTAssertTrue(waitForValue(status, value: "Preview ready for UI Test", timeout: 8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        attachScreenshot("preview")

        // AppKit hosts this modal alert outside the target's XCUI hierarchy on
        // macOS 14. Return activates its accessible default Apply action.
        app.typeKey(.return, modifierFlags: [])
        attachScreenshot("applying")
        XCTAssertTrue(waitForPath(destination, exists: true, timeout: 8))
        XCTAssertTrue(waitForValue(status, value: "UI Test applied successfully", timeout: 8))
        attachScreenshot("success")

        let undo = window.descendants(matching: .any)["undo-last-apply"]
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
        let heading = window.descendants(matching: .any)["invalid-profiles-heading"]
        let invalidProfile = window.descendants(matching: .any)["invalid-profile-Broken"]
        XCTAssertTrue(reveal(heading, in: window))
        XCTAssertTrue(reveal(invalidProfile, in: window))
        let labelPrefix = "Invalid profile Broken: "
        XCTAssertTrue(invalidProfile.label.hasPrefix(labelPrefix))
        XCTAssertGreaterThan(invalidProfile.label.count, labelPrefix.count)
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

    private func openPreview() {
        let window = app.windows["RiceBarMac Settings"]
        let button = window.descendants(matching: .any)["preview-selected-profile"]
        XCTAssertTrue(reveal(button, in: window))
        XCTAssertTrue(button.isEnabled)
        button.click()
    }

    private func reveal(_ element: XCUIElement, in window: XCUIElement) -> Bool {
        let scrollView = window.scrollViews.firstMatch
        guard scrollView.waitForExistence(timeout: 2) else { return false }
        if isVisiblyHittable(element, in: scrollView) { return true }

        let deltas: [CGFloat] = [-250, -250, -250, -250, -250, -250, 250, 250, 250]
        for delta in deltas {
            scrollView.scroll(byDeltaX: 0, deltaY: delta)
            if isVisiblyHittable(element, in: scrollView) { return true }
        }
        return isVisiblyHittable(element, in: scrollView)
    }

    private func isVisiblyHittable(_ element: XCUIElement, in container: XCUIElement) -> Bool {
        guard element.exists, element.isHittable else { return false }
        let frame = element.frame
        guard !frame.isNull, !frame.isInfinite, frame.width > 0, frame.height > 0 else { return false }
        return container.frame.insetBy(dx: 2, dy: 2).contains(
            CGPoint(x: frame.midX, y: frame.midY)
        )
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
