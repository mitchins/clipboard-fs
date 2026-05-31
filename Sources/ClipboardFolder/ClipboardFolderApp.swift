import AppKit
import ClipboardFolderUI
import OSLog
import SwiftUI

private let logger = Logger(subsystem: "com.mitchellcurrie.ClipboardFolder", category: "App")

@main
struct ClipboardFolderApp: App {
    @StateObject private var appState = AppState()

    private static let menuBarIconSize = NSSize(width: 18, height: 18)

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
        } label: {
            Image(nsImage: Self.menuBarIconImage)
                .renderingMode(.template)
        }

        Settings {
            SettingsView(appIcon: Self.settingsIconImage)
                .environmentObject(appState)
        }
    }

    private static var menuBarIconBundles: [Bundle] {
        #if SWIFT_PACKAGE
        [Bundle.module, .main]
        #else
        [.main]
        #endif
    }

    private static var menuBarIconImage: NSImage {
        if let image = loadMenuBarIcon() {
            return image
        }

        let bundleList = menuBarIconBundles
            .map { $0.bundleURL.lastPathComponent }
            .joined(separator: ", ")
        let message = "MenuBarIcon resource not found in bundles: \(bundleList)"
        logger.error("\(message)")
        assertionFailure(message)

        let fallback = NSImage(
            systemSymbolName: "questionmark.circle",
            accessibilityDescription: "Missing menu bar icon"
        )
            ?? NSImage()
        fallback.isTemplate = true
        fallback.size = menuBarIconSize
        return fallback
    }

    private static func loadMenuBarIcon() -> NSImage? {
        let candidates = ["MenuBarIcon@3x", "MenuBarIcon@2x", "MenuBarIcon"]

        for bundle in menuBarIconBundles {
            if let image = bundle.image(forResource: "MenuBarIcon") {
                return configuredMenuBarIcon(image)
            }

            for candidate in candidates {
                guard let url = bundledMenuBarIconURL(
                    candidate: candidate,
                    bundle: bundle
                ),
                      let image = NSImage(contentsOf: url)
                else {
                    continue
                }

                return configuredMenuBarIcon(image)
            }
        }

        return nil
    }

    private static var settingsIconImage: NSImage {
        guard let image = loadMenuBarIcon() else {
            let message = "MenuBarIcon resource not found for settings view"
            logger.error("\(message)")
            assertionFailure(message)
            return NSImage()
        }
        guard let settings = image.copy() as? NSImage else { return image }
        settings.isTemplate = false
        settings.size = NSSize(width: 64, height: 64)
        return settings
    }

    private static func configuredMenuBarIcon(_ image: NSImage) -> NSImage {
        image.isTemplate = true
        image.size = menuBarIconSize
        return image
    }

    private static func bundledMenuBarIconURL(
        candidate: String,
        bundle: Bundle
    ) -> URL? {
        let subdirectory = "Assets.xcassets/MenuBarIcon.imageset"

        if let url = bundle.url(
            forResource: candidate,
            withExtension: "png",
            subdirectory: subdirectory
        ) {
            return url
        }

        return bundle.url(forResource: candidate, withExtension: "png")
    }
}
