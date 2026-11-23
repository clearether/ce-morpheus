// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ce-morpheus",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "ce-morpheus")
    ],
    swiftLanguageModes: [.v6]
)
