// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Airstrip",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Airstrip", targets: ["Airstrip"])
    ],
    targets: [
        .executableTarget(
            name: "Airstrip",
            path: "Sources/Airstrip"
        )
    ]
)
