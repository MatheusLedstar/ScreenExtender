// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ScreenExtender",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "VirtualDisplayBridge",
            path: "Sources/VirtualDisplayBridge",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedFramework("CoreGraphics"),
            ]
        ),
        .executableTarget(
            name: "ScreenExtender",
            dependencies: ["VirtualDisplayBridge"],
            path: "Sources/ScreenExtender"
        ),
    ]
)
