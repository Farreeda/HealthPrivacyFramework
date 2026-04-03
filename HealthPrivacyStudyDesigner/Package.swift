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
            name: "Demo",
            targets: ["Demo"]
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
            name: "Demo",
            dependencies: ["HealthPrivacyStudyDesigner"],
            path: "Sources/Demo"
        ),
        .testTarget(
            name: "HealthPrivacyStudyDesignerTests",
            dependencies: ["HealthPrivacyStudyDesigner"],
            path: "Tests/HealthPrivacyStudyDesignerTests"
        ),
    ]
)
