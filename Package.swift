// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Sanity",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Sanity",
            path: "Sources/Sanity"
        )
    ]
)
