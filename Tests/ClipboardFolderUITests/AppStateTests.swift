import AppKit
import ClipboardFolderCore
import XCTest
import SwiftUI
@testable import ClipboardFolderUI

// MARK: - Mock

final class MockContentWriter: ContentWriting {
    struct WriteImageCall {
        let data: Data
        let filename: String
    }

    var writeImageCalls: [WriteImageCall] = []
    var copyFilesCalls: [[URL]] = []
    var clearCallCount = 0
    var stubbedFiles: [String] = []
    var stubbedUsedBytes: Int64 = 0
    var errorToThrow: Error?

    func currentFiles() -> [String] { stubbedFiles }
    func usedBytes() -> Int64 { stubbedUsedBytes }

    func clear() throws {
        clearCallCount += 1
        if let error = errorToThrow { throw error }
    }

    func writeImage(_ data: Data, filename: String) throws {
        if let error = errorToThrow { throw error }
        writeImageCalls.append(WriteImageCall(data: data, filename: filename))
    }

    func copyFiles(_ urls: [URL]) throws {
        if let error = errorToThrow { throw error }
        copyFilesCalls.append(urls)
    }
}

// MARK: - Tests

@MainActor
final class AppStateTests: XCTestCase {
    var mock: MockContentWriter!
    var state: AppState!

    override func setUp() {
        super.setUp()
        mock = MockContentWriter()
        state = AppState(contentWriter: mock)
    }

    // MARK: handleContent — image

    func test_handleContent_image_callsWriteImage() {
        let data = Data([0xFF, 0xD8, 0xFF])
        state.handleContent(.image(data, suggestedName: "photo.png"))
        XCTAssertEqual(mock.writeImageCalls.count, 1)
        XCTAssertEqual(mock.writeImageCalls[0].data, data)
        XCTAssertEqual(mock.writeImageCalls[0].filename, "photo.png")
    }

    func test_handleContent_image_setsCurrentFileName() {
        state.handleContent(.image(Data([0x89, 0x50]), suggestedName: "snap.png"))
        XCTAssertEqual(state.currentFileName, "snap.png")
    }

    func test_handleContent_image_clearsErrorMessage() {
        state.errorMessage = "previous error"
        state.handleContent(.image(Data([0x01]), suggestedName: "x.png"))
        XCTAssertNil(state.errorMessage)
    }

    // MARK: handleContent — files

    func test_handleContent_files_callsCopyFiles() {
        let urls = [URL(fileURLWithPath: "/tmp/a.txt"), URL(fileURLWithPath: "/tmp/b.txt")]
        state.handleContent(.files(urls))
        XCTAssertEqual(mock.copyFilesCalls.count, 1)
        XCTAssertEqual(mock.copyFilesCalls[0], urls)
    }

    func test_handleContent_files_setsCurrentFileNameFromFirstURL() {
        let urls = [URL(fileURLWithPath: "/tmp/report.pdf"), URL(fileURLWithPath: "/tmp/data.csv")]
        state.handleContent(.files(urls))
        XCTAssertEqual(state.currentFileName, "report.pdf")
    }

    // MARK: handleContent — empty

    func test_handleContent_empty_callsClear() {
        state.handleContent(.empty)
        XCTAssertEqual(mock.clearCallCount, 1)
    }

    func test_handleContent_empty_nilsCurrentFileName() {
        state.currentFileName = "old.png"
        state.handleContent(.empty)
        XCTAssertNil(state.currentFileName)
    }

    // MARK: handleContent — error propagation

    func test_handleContent_error_setsErrorMessage() {
        mock.errorToThrow = ContentWriterError.writeFailed("disk full")
        state.handleContent(.image(Data([0x01]), suggestedName: "x.png"))
        XCTAssertNotNil(state.errorMessage)
        XCTAssertTrue(state.errorMessage?.contains("disk full") == true)
    }

    func test_handleContent_subsequentSuccess_clearsErrorMessage() {
        mock.errorToThrow = ContentWriterError.writeFailed("oops")
        state.handleContent(.image(Data([0x01]), suggestedName: "x.png"))
        XCTAssertNotNil(state.errorMessage)

        mock.errorToThrow = nil
        state.handleContent(.image(Data([0x02]), suggestedName: "y.png"))
        XCTAssertNil(state.errorMessage)
    }

    // MARK: handleContent — refreshVolumeStats

    func test_handleContent_updatesFileCountAndUsedBytes() {
        mock.stubbedFiles = ["a.png", "b.png"]
        mock.stubbedUsedBytes = 1_024
        state.handleContent(.image(Data([0x01]), suggestedName: "a.png"))
        XCTAssertEqual(state.fileCount, 2)
        XCTAssertEqual(state.usedBytes, 1_024)
    }

    func test_settingsViewBodyBuilds() {
        let host = NSHostingView(
            rootView: SettingsView(appIcon: NSImage(size: NSSize(width: 64, height: 64)))
                .environmentObject(state)
        )
        host.frame = NSRect(x: 0, y: 0, width: 300, height: 400)
        host.layoutSubtreeIfNeeded()
    }

    // MARK: clearVolume

    func test_clearVolume_callsContentWriterClear() {
        state.clearVolume()
        XCTAssertEqual(mock.clearCallCount, 1)
    }

    func test_clearVolume_nilsCurrentFileName() {
        state.currentFileName = "old.png"
        state.clearVolume()
        XCTAssertNil(state.currentFileName)
    }

    func test_clearVolume_error_setsErrorMessage() {
        mock.errorToThrow = ContentWriterError.volumeNotAvailable
        state.clearVolume()
        XCTAssertNotNil(state.errorMessage)
    }
}
