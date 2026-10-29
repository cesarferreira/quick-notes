// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "QuickNotes",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "quick-notes", targets: ["QuickNotes"])],
    targets: [
        .target(name: "QuickNotesCore"),
        .executableTarget(name: "QuickNotes", dependencies: ["QuickNotesCore"]),
        .testTarget(name: "QuickNotesCoreTests", dependencies: ["QuickNotesCore"]),
        .testTarget(name: "QuickNotesTests", dependencies: ["QuickNotes", "QuickNotesCore"])
    ],
    swiftLanguageModes: [.v5]
)
