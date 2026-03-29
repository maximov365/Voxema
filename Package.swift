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
        // Thin C bridge for whisper.cpp.
        // whisper_stub.c provides no-op implementations so the app compiles and
        // tests run without the real library. Replace or augment it with the
        // real whisper.cpp + ggml sources (or a .binaryTarget) at model-integration time.
        .target(
            name: "CWhisper",
            path: "Voxema/Bridge/CWhisper",
            publicHeadersPath: "include"
        ),
        .executableTarget(
            name: "Voxema",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "Sparkle", package: "Sparkle"),
                "CWhisper",
            ],
            path: "Voxema",
            exclude: [
                "Info.plist",
                "Voxema.entitlements",
                "Resources/Models",
                "Resources/Prompts",
                "Bridge",
            ]
        ),
        .testTarget(
            name: "VoxemaTests",
            dependencies: ["Voxema"],
            path: "VoxemaTests"
        ),
    ]
)
