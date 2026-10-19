// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "miaokon-mac",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "miaokon-mac", targets: ["TracepadMac"])
    ],
    targets: [
        .target(
            name: "DockSwipe",
            path: "Sources/DockSwipe",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedFramework("CoreGraphics"),
                .linkedFramework("CoreFoundation"),
            ]
        ),
        .executableTarget(
            name: "TracepadMac",
            dependencies: ["DockSwipe"],
            path: "Sources/TracepadMac",
            linkerSettings: [
                .linkedFramework("CoreGraphics"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("AppKit"),
            ]
        )
    ]
)
