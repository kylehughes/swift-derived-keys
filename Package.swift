// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "DerivedKeys",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [
        .library(name: "DerivedKeys", targets: ["DerivedKeys"]),
        .library(name: "DerivedKeysUIKit", targets: ["DerivedKeysUIKit"]),
        .library(name: "DerivedKeysUI", targets: ["DerivedKeysUI"]),
        .executable(name: "DocumentExportExample", targets: ["DocumentExportExample"]),
        .executable(name: "DerivedKeysBenchmarks", targets: ["DerivedKeysBenchmarks"]),
    ],
    targets: [
        .target(name: "DerivedKeys", swiftSettings: [.treatAllWarnings(as: .error)]),
        .target(
            name: "DerivedKeysUIKit",
            dependencies: ["DerivedKeys"],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        .target(
            name: "DerivedKeysUI",
            dependencies: ["DerivedKeys", "DerivedKeysUIKit"],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        .target(
            name: "DerivedKeysUIExample",
            dependencies: ["DerivedKeys", "DerivedKeysUIKit", "DerivedKeysUI"],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        .executableTarget(
            name: "DocumentExportExample",
            dependencies: ["DerivedKeys"],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        .executableTarget(
            name: "DerivedKeysBenchmarks",
            dependencies: ["DerivedKeys", "DerivedKeysUI"],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        .testTarget(
            name: "DerivedKeysTests",
            dependencies: ["DerivedKeys"],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        .testTarget(
            name: "DerivedKeysUIKitTests",
            dependencies: ["DerivedKeys", "DerivedKeysUIKit"],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        .testTarget(
            name: "DerivedKeysUITests",
            dependencies: ["DerivedKeys", "DerivedKeysUI"],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        .testTarget(
            name: "DerivedKeysUIExampleTests",
            dependencies: ["DerivedKeysUIExample", "DerivedKeysUIKit", "DerivedKeysUI"],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
    ],
    swiftLanguageModes: [.v6]
)
