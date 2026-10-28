// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "WarningPolicy",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "WarningLibrary", swiftSettings: [.treatAllWarnings(as: .error)]),
        .executableTarget(name: "WarningExecutable", swiftSettings: [.treatAllWarnings(as: .error)]),
        .testTarget(
            name: "WarningTests",
            dependencies: ["WarningLibrary"],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
    ],
    swiftLanguageModes: [.v6]
)
