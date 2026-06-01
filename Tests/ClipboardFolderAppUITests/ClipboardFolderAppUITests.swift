import XCTest

final class ClipboardFolderAppUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchesWithoutMountingProductionVolume() throws {
        let app = XCUIApplication()
        app.launchEnvironment["CLIPDISK_SKIP_STARTUP"] = "1"
        app.launchEnvironment["CLIPDISK_VOLUME_NAME"] = "ClipDisk-Test"
        app.launch()

        XCTAssertTrue(
            waitForLaunchedAppState(app, timeout: 10),
            "Expected ClipDisk app process to launch (foreground or background)"
        )
        XCTAssertTrue(app.menuBars.firstMatch.exists)
    }

    private func waitForLaunchedAppState(_ app: XCUIApplication, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if app.state == .runningForeground || app.state == .runningBackground {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return false
    }
}
