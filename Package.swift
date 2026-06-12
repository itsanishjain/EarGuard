// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "EarGuard",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "EarGuard", targets: ["EarGuard"])
    ],
    targets: [
        .executableTarget(
            name: "EarGuard",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("UserNotifications"),
                .linkedFramework("ServiceManagement")
            ]
        )
    ]
)
