// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FocusCull",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "FocusCull", targets: ["FocusCull"]),
        .executable(name: "focuscull-tool", targets: ["FocusCullTool"])
    ],
    targets: [
        .target(
            name: "FocusCullCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "FocusCull",
            dependencies: ["FocusCullCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "FocusCullTool",
            dependencies: ["FocusCullCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
