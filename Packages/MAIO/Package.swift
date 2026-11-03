// swift-tools-version: 6.2
// MAIO 模块边界在此声明，规则见 docs/ARCHITECTURE.md §2。
import PackageDescription

/// ★ 所有功能模块（不带 "Feature" 前缀）。`make new-feature` 会自动在标记处追加。
/// 每个功能只能依赖 MAIOKit 和 MAIOUI，不要在这里给单个功能加例外依赖。
let features: [String] = [
    "SystemActions",
    "Scroll",
    "Switcher",
    "Translate",
    "Clipboard",
    "Screenshot",
    // @new-feature-marker
]

let strict: [SwiftSetting] = [.treatAllWarnings(as: .error)]

let featureTargets: [Target] = features.flatMap { name -> [Target] in
    [
        .target(
            name: "Feature\(name)",
            dependencies: ["MAIOKit", "MAIOUI"],
            exclude: ["README.md"],
            swiftSettings: strict,
        ),
        .testTarget(
            name: "Feature\(name)Tests",
            dependencies: [.target(name: "Feature\(name)"), "MAIOTesting"],
            swiftSettings: strict,
        ),
    ]
}

let package = Package(
    name: "MAIO",
    platforms: [.macOS(.v26)],
    products: [
        // App 壳只依赖这一个产品
        .library(name: "MAIOApp", targets: ["MAIOShell"] + features.map { "Feature\($0)" }),
    ],
    targets: [
        .target(name: "MAIOKit", exclude: ["Contracts/README.md"], swiftSettings: strict),
        .target(name: "MAIOUI", dependencies: ["MAIOKit"], swiftSettings: strict),
        .target(name: "MAIOCore", dependencies: ["MAIOKit"], swiftSettings: strict),
        .target(name: "MAIOShell", dependencies: ["MAIOKit", "MAIOUI", "MAIOCore"], swiftSettings: strict),
        .target(name: "MAIOTesting", dependencies: ["MAIOKit"], swiftSettings: strict),
        .testTarget(name: "MAIOKitTests", dependencies: ["MAIOKit"], swiftSettings: strict),
        .testTarget(name: "MAIOCoreTests", dependencies: ["MAIOCore", "MAIOTesting"], swiftSettings: strict),
    ] + featureTargets,
)
