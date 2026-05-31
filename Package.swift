// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "ClipboardFolder",
    platforms: [.macOS(.v14)],
    products: [
        .library(
            name: "ClipboardFolderCore",
            targets: ["ClipboardFolderCore"]
        ),
        .library(
            name: "ClipboardFolderUI",
            targets: ["ClipboardFolderUI"]
        ),
        .executable(
            name: "ClipboardFolder",
            targets: ["ClipboardFolder"]
        ),
    ],
    targets: [
        .target(
            name: "ClipboardFolderCore",
            path: "Sources/ClipboardFolderCore"
        ),
        .target(
            name: "ClipboardFolderUI",
            dependencies: ["ClipboardFolderCore"],
            path: "Sources/ClipboardFolderUI"
        ),
        .executableTarget(
            name: "ClipboardFolder",
            dependencies: ["ClipboardFolderUI"],
            path: "Sources/ClipboardFolder",
            resources: [
                .process("Assets.xcassets"),
                .copy("Assets.xcassets/MenuBarIcon.imageset/MenuBarIcon.png"),
                .copy("Assets.xcassets/MenuBarIcon.imageset/MenuBarIcon@2x.png"),
                .copy("Assets.xcassets/MenuBarIcon.imageset/MenuBarIcon@3x.png"),
            ]
        ),
        .testTarget(
            name: "ClipboardFolderCoreTests",
            dependencies: ["ClipboardFolderCore"],
            path: "Tests/ClipboardFolderCoreTests"
        ),
        .testTarget(
            name: "ClipboardFolderIntegrationTests",
            dependencies: ["ClipboardFolderCore"],
            path: "Tests/ClipboardFolderIntegrationTests"
        ),
        .testTarget(
            name: "ClipboardFolderUITests",
            dependencies: ["ClipboardFolderUI"],
            path: "Tests/ClipboardFolderUITests"
        ),
    ]
)
