// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RazerNommoControl",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "RazerNommoControl",
            path: "Sources/RazerNommoControl"
        )
    ]
)
