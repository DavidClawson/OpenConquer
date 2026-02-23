// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TiberianDawnMax",
    platforms: [.macOS(.v13)],
    targets: [
        .systemLibrary(
            name: "CSDL2",
            pkgConfig: "sdl2",
            providers: [.brew(["sdl2"])]
        ),
        .executableTarget(
            name: "TiberianDawnMax",
            dependencies: ["CSDL2"],
            path: "Sources/TiberianDawnMax"
        ),
    ]
)
