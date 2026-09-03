// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "UVieKey",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "UVieKey", targets: ["UVieKey"])
    ],
    targets: [
        .executableTarget(
            name: "UVieKey",
            dependencies: [],
            swiftSettings: [
                .unsafeFlags(["-F", "Frameworks"], .when(platforms: [.macOS])),
            ],
            linkerSettings: [
                .linkedFramework("Cocoa"),
                .linkedFramework("Carbon"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("Sparkle"),
                .linkedLibrary("uvie"),
                .unsafeFlags(["-F", "Frameworks"], .when(platforms: [.macOS])),
                .unsafeFlags(["-LFrameworks"], .when(platforms: [.macOS])),
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@loader_path/../Frameworks"], .when(platforms: [.macOS])),
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@loader_path/../../../Frameworks"], .when(platforms: [.macOS])),
            ]
        ),
        .testTarget(
            name: "UVieKeyTests",
            dependencies: ["UVieKey"],
            swiftSettings: [
                .unsafeFlags(["-F", "Frameworks"], .when(platforms: [.macOS])),
            ],
            linkerSettings: [
                .linkedFramework("Cocoa"),
                .linkedFramework("Carbon"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("Sparkle"),
                .linkedLibrary("uvie"),
                .unsafeFlags(["-F", "Frameworks"], .when(platforms: [.macOS])),
                .unsafeFlags(["-LFrameworks"], .when(platforms: [.macOS])),
                // xctest bundle lives at
                // .build/<triple>/debug/<Tests>.xctest/Contents/MacOS — six
                // levels up is the package root, where Frameworks/ (Sparkle)
                // resides.
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@loader_path/../../../../../../Frameworks"], .when(platforms: [.macOS])),
            ]
        ),
    ]
)
