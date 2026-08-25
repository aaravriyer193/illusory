// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Illusory",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Illusory", path: "Sources/Illusory")
    ]
)
