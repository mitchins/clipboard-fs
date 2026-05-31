import XCTest
@testable import ClipboardFolderUI

@MainActor
final class UpdateCheckerTests: XCTestCase {
    func testCheckSetsUpToDateWhenVersionsMatch() async {
        let checker = UpdateChecker(
            fetchLatestRelease: {
                (tagName: "v1.2.3", htmlURL: URL(string: "https://example.com/release")!)
            }
        )

        checker.check(current: "1.2.3")
        await waitForState(checker) {
            if case .upToDate = checker.state { return true }
            return false
        }

        if case .upToDate(let version) = checker.state {
            XCTAssertEqual(version, "1.2.3")
        } else {
            XCTFail("Expected upToDate state")
        }
    }

    func testCheckSetsAvailableWhenVersionsDiffer() async {
        let releaseURL = URL(string: "https://example.com/release")!
        let checker = UpdateChecker(
            fetchLatestRelease: {
                (tagName: "v2.0.0", htmlURL: releaseURL)
            }
        )

        checker.check(current: "v1.9.0")
        await waitForState(checker) {
            if case .available = checker.state { return true }
            return false
        }

        if case .available(let current, let latest, let url) = checker.state {
            XCTAssertEqual(current, "v1.9.0")
            XCTAssertEqual(latest, "v2.0.0")
            XCTAssertEqual(url, releaseURL)
        } else {
            XCTFail("Expected available state")
        }
    }

    func testCheckSetsFailedWhenFetchThrows() async {
        struct FakeError: LocalizedError {
            let errorDescription: String? = "network boom"
        }

        let checker = UpdateChecker(
            fetchLatestRelease: {
                throw FakeError()
            }
        )

        checker.check(current: "1.0.0")
        await waitForState(checker) {
            if case .failed = checker.state { return true }
            return false
        }

        if case .failed(let message) = checker.state {
            XCTAssertEqual(message, "network boom")
        } else {
            XCTFail("Expected failed state")
        }
    }

    private func waitForState(
        _ checker: UpdateChecker,
        timeout: TimeInterval = 1.0,
        condition: @escaping @MainActor () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("Timed out waiting for expected update checker state")
    }
}
