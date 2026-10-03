// swift-tools-version: 5.9
import PackageDescription

// Three layers, each depending only on the ones above it:
//   OpenConquerAssets  — archive and file formats (MIX, SHP, ICN, INI, AUD)
//   OpenConquerCore    — the simulation: data tables, rules, scenarios.
//                        Never imports SDL; must stay deterministic.
//   TiberianDawnMax    — the app: SDL, rendering, audio, UI, headless tools.
// Cross-module declarations use `package` access (visible within this
// package only).
let package = Package(
    name: "TiberianDawnMax",
    platforms: [.macOS(.v13)],
    targets: [
        .systemLibrary(
            name: "CSDL2",
            pkgConfig: "sdl2",
            providers: [.brew(["sdl2"])]
        ),
        .target(name: "OpenConquerAssets"),
        .target(name: "OpenConquerCore", dependencies: ["OpenConquerAssets"]),
        .executableTarget(
            name: "TiberianDawnMax",
            dependencies: ["CSDL2", "OpenConquerCore", "OpenConquerAssets"]
        ),
    ]
)
