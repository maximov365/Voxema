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
        // Thin C bridge for whisper.cpp (stub pattern — see DEC-4).
        .target(
            name: "CWhisper",
            path: "Voxema/Bridge/CWhisper",
            publicHeadersPath: "include"
        ),
        // Thin C bridge for ECAPA-TDNN via ONNX Runtime (stub pattern — see DEC-5).
        // voxema_ecapa_stub.c returns zero embeddings; replace with real ORT implementation.
        .target(
            name: "COnnxRuntime",
            path: "Voxema/Bridge/COnnxRuntime",
            publicHeadersPath: "include"
        ),
        .executableTarget(
            name: "Voxema",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "Sparkle", package: "Sparkle"),
                "CWhisper",
                "COnnxRuntime",
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
