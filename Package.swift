// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MacSpeed",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "MacSpeed",
            path: "Sources/MacSpeed"
        )
    ]
)
