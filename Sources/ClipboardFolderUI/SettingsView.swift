import SwiftUI

public struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var updater = UpdateChecker()
    private let appIcon: NSImage

    public init(appIcon: NSImage) {
        self.appIcon = appIcon
    }

    public var body: some View {
        VStack(spacing: 0) {
            // App identity
            VStack(spacing: 8) {
                Image(nsImage: appIcon)
                    .resizable()
                    .frame(width: 64, height: 64)
                Text("ClipDisk")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .accessibilityIdentifier("settings.appName")
                Text("Version \(AppState.versionDisplay)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("settings.version")
            }
            .padding(.top, 24)
            .padding(.bottom, 16)

            Divider()

            // Update check
            VStack(spacing: 8) {
                updateStatusView
                Button("Check for Updates") {
                    updater.check(current: AppState.version)
                }
                .accessibilityIdentifier("settings.checkUpdates")
                .disabled({
                    if case .checking = updater.state { return true }
                    return false
                }())
            }
            .padding(.vertical, 14)

            Divider()

            // Settings
            HStack {
                Text("Launch at Login")
                Spacer()
                Toggle("", isOn: Binding(
                    get: { appState.launchAtLogin },
                    set: { _ in appState.toggleLaunchAtLogin() }
                ))
                .accessibilityIdentifier("settings.launchAtLogin")
                .labelsHidden()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Divider()

            // Footer
            HStack {
                Link("View on GitHub", destination: URL(string: "https://github.com/mitchins/clipdisk")!)
                    .font(.footnote)
            }
            .padding(.vertical, 12)
        }
        .frame(width: 300)
        .accessibilityIdentifier("settings.root")
    }

    @ViewBuilder
    private var updateStatusView: some View {
        switch updater.state {
        case .idle:
            EmptyView()
        case .checking:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Checking…").font(.caption).foregroundStyle(.secondary)
            }
        case .upToDate(let version):
            Label("Up to date (\(version))", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case .available(_, let latest, let url):
            VStack(spacing: 4) {
                Label("\(latest) available", systemImage: "arrow.down.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                Link("See release notes", destination: url)
                    .font(.caption)
            }
        case .failed(let msg):
            Label(msg, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(2)
        }
    }
}
