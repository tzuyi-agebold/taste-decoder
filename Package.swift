// swift-tools-version:5.9
// Builds only the Foundation-only core logic so it can be unit-tested with `swift test`
// on any machine (macOS or Linux). The app itself is built from project.yml with Xcode.
import PackageDescription

let package = Package(
    name: "TasteCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    targets: [
        .target(
            name: "TasteCore",
            path: "TasteDecoder/Core"
        ),
        .testTarget(
            name: "TasteCoreTests",
            dependencies: ["TasteCore"],
            path: "Tests/TasteCoreTests"
        ),
    ]
)
