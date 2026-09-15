// swift-tools-version:6.0
import PackageDescription
import Foundation

let packageRoot = FileManager.default.currentDirectoryPath
let frameworksPath = URL(fileURLWithPath: packageRoot)
    .appendingPathComponent("Frameworks").path

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
                .unsafeFlags(["-F", frameworksPath], .when(platforms: [.macOS])),
                .swiftLanguageMode(.v5),
            ],
            linkerSettings: [
                .linkedFramework("Cocoa"),
                .linkedFramework("Carbon"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("Sparkle"),
                .linkedLibrary("uvie"),
                .unsafeFlags(["-F", frameworksPath], .when(platforms: [.macOS])),
                .unsafeFlags(["-L", frameworksPath], .when(platforms: [.macOS])),
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@loader_path/../Frameworks"], .when(platforms: [.macOS])),
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@loader_path/../../../Frameworks"], .when(platforms: [.macOS])),
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@loader_path/../../../../Frameworks"], .when(platforms: [.macOS])),
            ]
        ),
        .testTarget(
            name: "UVieKeyTests",
            dependencies: ["UVieKey"],
            swiftSettings: [
                .unsafeFlags(["-F", frameworksPath], .when(platforms: [.macOS])),
                .swiftLanguageMode(.v5),
            ],
            linkerSettings: [
                .linkedFramework("Cocoa"),
                .linkedFramework("Carbon"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("Sparkle"),
                .linkedLibrary("uvie"),
                .unsafeFlags(["-F", frameworksPath], .when(platforms: [.macOS])),
                .unsafeFlags(["-L", frameworksPath], .when(platforms: [.macOS])),
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@loader_path/../../../../../../Frameworks"], .when(platforms: [.macOS])),
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@loader_path/../../../../../../../Frameworks"], .when(platforms: [.macOS])),
            ]
        ),
    ]
)
