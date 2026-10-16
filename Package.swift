// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "EXdl",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "EXdl", targets: ["EXdl"]),
        .executable(name: "EXdlStubLauncher", targets: ["EXdlStubLauncher"])
    ],
    targets: [
        .executableTarget(
            name: "EXdl",
            path: "Sources/EXdl"
        ),
        .executableTarget(
            name: "EXdlStubLauncher",
            path: "Sources/StubLauncher"
        )
    ]
)
