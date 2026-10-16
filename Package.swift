// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "HariciKur",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "HariciKur", targets: ["HariciKur"]),
        .executable(name: "HariciKurStubLauncher", targets: ["HariciKurStubLauncher"])
    ],
    targets: [
        .executableTarget(
            name: "HariciKur",
            path: "Sources/HariciKur"
        ),
        .executableTarget(
            name: "HariciKurStubLauncher",
            path: "Sources/StubLauncher"
        )
    ]
)
