// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "IBAKeyMorph",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "IBAKeyMorph", targets: ["IBAKeyMorph"]),
        .library(name: "KeyMorphCore", targets: ["KeyMorphCore"]),
    ],
    targets: [
        .target(name: "KeyMorphCore"),
        .executableTarget(
            name: "IBAKeyMorph",
            dependencies: ["KeyMorphCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("IOKit"),
            ]
        ),
        .testTarget(name: "KeyMorphCoreTests", dependencies: ["KeyMorphCore"]),
    ]
)
