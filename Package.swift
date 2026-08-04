// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TaskWidgets",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "TaskWidgets",
            path: "Sources/TaskWidgets"
        )
    ]
)
