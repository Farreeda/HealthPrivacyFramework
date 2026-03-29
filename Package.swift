// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HealthPrivacyStudyDesigner",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
    ],
    products: [
        .library(
            name: "HealthPrivacyStudyDesigner",
            targets: ["HealthPrivacyStudyDesigner"]
        ),
        .executable(
            name: "hpsd-demo",
            targets: ["HPSDDemo"]
        ),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "HealthPrivacyStudyDesigner",
            dependencies: [],
            path: "Sources/HealthPrivacyStudyDesigner"
        ),
        .executableTarget(
            name: "HPSDDemo",
            dependencies: ["HealthPrivacyStudyDesigner"],
            path: "Sources/HPSDDemo"
        ),
        .testTarget(
            name: "HealthPrivacyStudyDesignerTests",
            dependencies: ["HealthPrivacyStudyDesigner"],
            path: "Tests/HealthPrivacyStudyDesignerTests"
        ),
    ]
)
