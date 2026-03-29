// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Voxema",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Voxema", targets: ["Voxema"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", from: "6.0.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "Voxema",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Voxema",
            exclude: [
                "Info.plist",
                "Voxema.entitlements",
                "Resources/Models",
                "Resources/Prompts",
            ]
        ),
        .testTarget(
            name: "VoxemaTests",
            dependencies: ["Voxema"],
            path: "VoxemaTests"
        ),
    ]
)
