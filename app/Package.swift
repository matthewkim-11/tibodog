// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "TiboDog",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "TiboDog",
            path: "Sources/TiboDog",
            linkerSettings: [
                .linkedFramework("Security"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .testTarget(name: "TiboDogTests", dependencies: ["TiboDog"])
    ]
)
