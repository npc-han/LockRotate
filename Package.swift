// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LockRotate",
    defaultLocalization: "en",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "LockRotateCore", targets: ["LockRotateCore"]),
        .library(name: "LockRotateSystem", targets: ["LockRotateSystem"]),
        .executable(name: "LockRotateApp", targets: ["LockRotateApp"]),
    ],
    targets: [
        .target(
            name: "LockRotateCore",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "LockRotateCoreTests",
            dependencies: ["LockRotateCore"]
        ),
        .target(
            name: "LockRotateSystem",
            resources: [
                // .copy keeps the scripts byte-for-byte: they are sent to root as-is.
                .copy("Resources/set-lock-text"),
                .copy("Resources/install-helper.sh"),
                .copy("Resources/uninstall-helper.sh"),
                .process("Resources/Localizable.xcstrings"),
            ]
        ),
        .testTarget(
            name: "LockRotateSystemTests",
            dependencies: ["LockRotateSystem"]
        ),
        .executableTarget(
            name: "LockRotateApp",
            dependencies: ["LockRotateCore", "LockRotateSystem"],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "LockRotateAppTests",
            dependencies: ["LockRotateApp", "LockRotateCore", "LockRotateSystem"]
        ),
    ]
)
