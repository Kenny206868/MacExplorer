// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacExplorer",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MacExplorer", targets: ["MacExplorer"]),
        .library(name: "ExplorerCore", targets: ["ExplorerCore"]),
        .executable(name: "RecoveryCrashProbe", targets: ["RecoveryCrashProbe"])
    ],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.6")],
    targets: [
        .systemLibrary(name: "CLibArchive", path: "Sources/CLibArchive"),
        .target(name: "CJournal", linkerSettings: [.linkedLibrary("sqlite3")]),
        .target(name: "ExplorerJournal", dependencies: ["CJournal"]),
        .target(name: "ExplorerCore", dependencies: ["CLibArchive", "ExplorerJournal"], linkerSettings: [.linkedLibrary("archive")]),
        .executableTarget(name: "RecoveryCrashProbe", dependencies: ["ExplorerJournal"]),
        .executableTarget(name: "MacExplorer", dependencies: ["ExplorerCore", .product(name: "Sparkle", package: "Sparkle")], linkerSettings: [.linkedFramework("AppKit"), .linkedFramework("QuickLookThumbnailing"), .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .testTarget(name: "ExplorerCoreTests", dependencies: ["ExplorerCore"]),
        .testTarget(name: "ExplorerJournalTests", dependencies: ["ExplorerJournal", "RecoveryCrashProbe"]),
        .testTarget(name: "MacExplorerUITests", dependencies: ["MacExplorer", "ExplorerCore"])
    ]
)
