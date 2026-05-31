import XCTest
@testable import ClipboardFolderCore

final class ProcessExecutorTests: XCTestCase {
    func testRunReturnsExitCodeAndTrimmedOutput() throws {
        let executor = SystemProcessExecutor()
        let result = try executor.run(
            executablePath: "/bin/sh",
            arguments: ["-c", "echo ' hello '; echo ' err ' >&2; exit 7"]
        )

        XCTAssertEqual(result.exitCode, 7)
        XCTAssertEqual(result.output, "hello")
        XCTAssertEqual(result.errorOutput, "err")
    }

    func testRunWithNonPositiveTimeoutUsesNonTimeoutPath() throws {
        let executor = SystemProcessExecutor()
        let result = try executor.run(
            executablePath: "/bin/echo",
            arguments: ["ok"],
            timeout: 0
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.output, "ok")
    }

    func testRunWithTimeoutThrowsTimedOutError() {
        let executor = SystemProcessExecutor()

        XCTAssertThrowsError(
            try executor.run(
                executablePath: "/bin/sh",
                arguments: ["-c", "sleep 2"],
                timeout: 0.2
            )
        ) { error in
            guard case ProcessExecutionError.timedOut(let executablePath, let timeout) = error else {
                XCTFail("Expected timedOut error, got \(error)")
                return
            }

            XCTAssertEqual(executablePath, "/bin/sh")
            XCTAssertEqual(timeout, 0.2, accuracy: 0.0001)
        }
    }

    func testTimedOutErrorDescriptionIncludesPathAndTimeout() {
        let error = ProcessExecutionError.timedOut(executablePath: "/bin/sh", timeout: 1.5)
        XCTAssertEqual(
            error.errorDescription,
            "Timed out after 1.5 seconds running /bin/sh"
        )
    }
}
