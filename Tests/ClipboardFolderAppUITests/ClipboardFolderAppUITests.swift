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
            app.wait(for: .runningForeground, timeout: 10),
            "Expected ClipDisk app process to launch in foreground"
        )
        XCTAssertTrue(app.menuBars.firstMatch.exists)
    }
}
