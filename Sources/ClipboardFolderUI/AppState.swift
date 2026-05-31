import AppKit
@preconcurrency import ClipboardFolderCore
import OSLog
import ServiceManagement
import SwiftUI

private let logger = Logger(subsystem: "com.mitchellcurrie.ClipboardFolder", category: "AppState")

private struct VolumeRecoveryRemountWork: @unchecked Sendable {
    let ramDiskManager: RAMDiskManager

    func perform() async throws {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [ramDiskManager] in
                do {
                    let recovered = (try? ramDiskManager.recoverExistingDisk()) ?? false
                    if !recovered {
                        logger.info("Recovering existing volume failed, creating a fresh one")
                        try ramDiskManager.setupFresh()
                    }

                    guard ramDiskManager.waitForMount() else {
                        throw RAMDiskError.creationFailed(
                            "Clipboard volume did not mount at \(ramDiskManager.mountPoint)"
                        )
                    }

                    continuation.resume()
                } catch {
                    logger.error("Remount failed: \(error.localizedDescription)")
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

@MainActor
public final class AppState: ObservableObject {
    @Published public var isMounted = false
    @Published public var currentFileName: String?
    @Published public var fileCount: Int = 0
    @Published public var usedBytes: Int64 = 0
    @Published public var launchAtLogin = false
    @Published public var errorMessage: String?
    public var mountPoint: String { ramDiskManager.mountPoint }

    static let version: String = {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }()

    static let build: String? = {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
    }()

    static var versionDisplay: String {
        if version != "dev" {
            if let buildVersion = build, !buildVersion.isEmpty, buildVersion != version {
                return "\(version) (\(buildVersion))"
            } else {
                return version
            }
        } else {
            return "dev"
        }
    }

    let ramDiskManager: RAMDiskManager
    let clipboardMonitor: ClipboardMonitor
    let contentWriter: any ContentWriting

    private var terminationObserver: Any?
    private var volumeRecoverySuccessObserver: Any?
    private var volumeHealthTimer: Timer?
    private var volumeRecoveryDialogController: VolumeRecoveryDialogController?

    private struct RuntimeOptions {
        let volumeName: String
        let sizeInMB: Int
        let shouldAutoStartup: Bool

        static func fromEnvironment(_ environment: [String: String]) -> RuntimeOptions {
            let rawVolumeName = environment["CLIPDISK_VOLUME_NAME"]?.trimmingCharacters(in: .whitespacesAndNewlines)
            let parsedSize = Int(environment["CLIPDISK_VOLUME_SIZE_MB"] ?? "")
            let shouldSkipStartup = environment["CLIPDISK_SKIP_STARTUP"] == "1"
            let resolvedVolumeName = rawVolumeName.flatMap { $0.isEmpty ? nil : $0 } ?? "Clipboard"
            return RuntimeOptions(
                volumeName: resolvedVolumeName,
                sizeInMB: max(1, parsedSize ?? 20),
                shouldAutoStartup: !shouldSkipStartup
            )
        }
    }

    public init() {
        let options = RuntimeOptions.fromEnvironment(ProcessInfo.processInfo.environment)
        let rdm = RAMDiskManager(volumeName: options.volumeName, sizeInMB: options.sizeInMB)
        self.ramDiskManager = rdm
        self.clipboardMonitor = ClipboardMonitor()
        self.contentWriter = ContentWriter(volumePath: rdm.mountPoint)
        self.launchAtLogin = SMAppService.mainApp.status == .enabled

        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.shutdown()
            }
        }

        installVolumeRecoverySuccessObserver()

        if options.shouldAutoStartup {
            Task { @MainActor in
                self.startup()
            }
        }
    }

    /// Test-only initializer — injects a `ContentWriting` stub, skips startup and system services.
    init(contentWriter: any ContentWriting) {
        self.ramDiskManager = RAMDiskManager()
        self.clipboardMonitor = ClipboardMonitor()
        self.contentWriter = contentWriter
        self.launchAtLogin = false

        installVolumeRecoverySuccessObserver()
    }

    deinit {
        if let observer = terminationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = volumeRecoverySuccessObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Lifecycle

    func startup() {
        do {
            let recovered = try ramDiskManager.recoverExistingDisk()
            if !recovered {
                try ramDiskManager.setup()
            }
            activateMountedVolume()
        } catch {
            presentVolumeRecoveryDialog(reason: error.localizedDescription)
            return
        }

        clipboardMonitor.delegate = self
        clipboardMonitor.start()
        startVolumeHealthMonitoring()
    }

    func shutdown() {
        clipboardMonitor.stop()
        stopVolumeHealthMonitoring()
        volumeRecoveryDialogController?.close()
        volumeRecoveryDialogController = nil
        try? ramDiskManager.teardown()
        isMounted = false
    }

    // MARK: - Actions

    public func openInFinder() {
        guard isMounted else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: ramDiskManager.mountPoint))
    }

    public func ejectAndQuit() {
        shutdown()
        NSApplication.shared.terminate(nil)
    }

    public func clearVolume() {
        do {
            try contentWriter.clear()
            currentFileName = nil
            refreshVolumeStats()
        } catch {
            handleVolumeFailure(error)
        }
    }

    func refreshVolumeStats() {
        let files = contentWriter.currentFiles()
        fileCount = files.count
        usedBytes = contentWriter.usedBytes()
    }

    public func toggleLaunchAtLogin() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
            launchAtLogin.toggle()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Content handling

    func handleContent(_ content: ClipboardContent) {
        do {
            switch content {
            case .image(let data, let name):
                try contentWriter.writeImage(data, filename: name)
                currentFileName = name
            case .files(let urls):
                try contentWriter.copyFiles(urls)
                currentFileName = urls.first?.lastPathComponent
            case .empty:
                try contentWriter.clear()
                currentFileName = nil
            }
            errorMessage = nil
            refreshVolumeStats()
        } catch {
            handleVolumeFailure(error)
        }
    }

    // MARK: - Volume recovery

    private func activateMountedVolume() {
        isMounted = true
        errorMessage = nil
        refreshVolumeStats()
        currentFileName = contentWriter.currentFiles().first
    }

    private func handleVolumeFailure(_ error: Error) {
        errorMessage = error.localizedDescription
        if shouldPromptForVolumeRecovery(error) {
            presentVolumeRecoveryDialog(reason: error.localizedDescription)
        }
    }

    private func shouldPromptForVolumeRecovery(_ error: Error) -> Bool {
        isMounted && !ramDiskManager.isMounted
    }

    private func startVolumeHealthMonitoring() {
        stopVolumeHealthMonitoring()
        volumeHealthTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkVolumeHealth()
            }
        }
    }

    private func stopVolumeHealthMonitoring() {
        volumeHealthTimer?.invalidate()
        volumeHealthTimer = nil
    }

    private func checkVolumeHealth() {
        guard volumeRecoveryDialogController == nil else { return }
        guard isMounted else { return }
        guard !ramDiskManager.isMounted else { return }

        presentVolumeRecoveryDialog(reason: "Clipboard volume unavailable.")
    }

    private func presentVolumeRecoveryDialog(reason: String) {
        guard volumeRecoveryDialogController == nil else { return }

        logger.warning("Presenting recovery dialog: \(reason)")
        clipboardMonitor.stop()
        stopVolumeHealthMonitoring()
        isMounted = false
        errorMessage = reason

        let remountWork = VolumeRecoveryRemountWork(ramDiskManager: ramDiskManager)

        let controller = VolumeRecoveryDialogController(
            reason: reason,
            remountAction: {
                try await remountWork.perform()
            },
            quitAction: { [weak self] in
                self?.ejectAndQuit()
            }
        )
        controller.onDidClose = { [weak self] in
            self?.volumeRecoveryDialogController = nil
        }
        volumeRecoveryDialogController = controller
        controller.present()
    }

    private func installVolumeRecoverySuccessObserver() {
        volumeRecoverySuccessObserver = NotificationCenter.default.addObserver(
            forName: .clipboardVolumeRecoveryRemountSucceeded,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            // Use RunLoop.main.perform so the block fires in NSModalPanelRunLoopMode.
            // DispatchQueue.main only drains in kCFRunLoopCommonModes, which does NOT
            // include NSModalPanelRunLoopMode, so queue: .main never executes while
            // NSApp.runModal is holding the event loop.
            RunLoop.main.perform(inModes: [.modalPanel, .default]) {
                MainActor.assumeIsolated {
                    self?.handleVolumeRecoveryRemountSucceeded()
                }
            }
        }
    }

    private func handleVolumeRecoveryRemountSucceeded() {
        volumeRecoveryDialogController?.close()
        finishRecoveredVolume()
    }

    private func finishRecoveredVolume() {
        activateMountedVolume()
        clipboardMonitor.delegate = self
        clipboardMonitor.start()
        startVolumeHealthMonitoring()
    }
}

// MARK: - ClipboardMonitorDelegate

extension AppState: ClipboardMonitorDelegate {
    nonisolated public func clipboardMonitor(
        _ monitor: ClipboardMonitor, didDetect content: ClipboardContent
    ) {
        Task { @MainActor in
            self.handleContent(content)
        }
    }
}
