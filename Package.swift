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
            linkerSettings: [
                .linkedFramework("Cocoa"),
                .linkedFramework("Carbon"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("ServiceManagement"),
                .linkedLibrary("uvie"),
                .unsafeFlags(["-LFrameworks"], .when(platforms: [.macOS])),
            ]
        )
    ]
)
