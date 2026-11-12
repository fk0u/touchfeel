// swift-tools-version:5.9
import PackageDescription

let strict: [SwiftSetting] = [.enableExperimentalFeature("StrictConcurrency")]

let package = Package(
    name: "TouchFeel",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "touchlog", targets: ["touchlog"]),
        .executable(name: "touchfeeld", targets: ["touchfeeld"]),
    ],
    targets: [
        // Foundation only (D4).
        .target(name: "TouchCore", swiftSettings: strict),
        .target(name: "Recognizer", dependencies: ["TouchCore"], swiftSettings: strict),
        // Only HIDInput touches IOKit; only EventOutput posts CGEvents.
        .target(
            name: "HIDInput", dependencies: ["TouchCore"], swiftSettings: strict,
            linkerSettings: [.linkedFramework("IOKit")]),
        .target(name: "EventOutput", dependencies: ["TouchCore"], swiftSettings: strict),
        .executableTarget(
            name: "touchlog", dependencies: ["TouchCore", "HIDInput"], path: "Tools/touchlog",
            swiftSettings: strict),
        .executableTarget(
            name: "touchfeeld", dependencies: ["TouchCore", "Recognizer", "HIDInput", "EventOutput"],
            swiftSettings: strict),
        .testTarget(name: "TouchCoreTests", dependencies: ["TouchCore"], swiftSettings: strict),
        .testTarget(name: "HIDInputTests", dependencies: ["HIDInput"], swiftSettings: strict),
        .testTarget(name: "RecognizerTests", dependencies: ["Recognizer"], swiftSettings: strict),
    ]
)
