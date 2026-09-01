// swift-tools-version: 6.0
import PackageDescription

let strict: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("InternalImportsByDefault"),
]

let package = Package(
    name: "Phosphor",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Phosphor", targets: ["Phosphor"]),
    ],
    targets: [
        // Shared primitives: no dependencies, no I/O.
        .target(name: "PhosphorCore", swiftSettings: strict),

        // Encrypted profile container and atomic writes.
        .target(name: "VaultKit", dependencies: ["PhosphorCore"], swiftSettings: strict),

        // Hosts, groups, tags, ssh_config import, snippets.
        .target(name: "HostsKit", dependencies: ["PhosphorCore"], swiftSettings: strict),

        // Transport abstraction over ssh(1); proxy and jump support.
        .target(name: "SSHKit", dependencies: ["PhosphorCore", "HostsKit"], swiftSettings: strict),

        // Container listing, stats and log streaming over SSH.
        .target(name: "DockerKit", dependencies: ["PhosphorCore", "SSHKit"], swiftSettings: strict),

        // /proc snapshot parsing and ring buffers.
        .target(name: "MetricsKit", dependencies: ["PhosphorCore", "SSHKit"], swiftSettings: strict),

        // authorized_keys parsing, fingerprints, safe rewrites.
        .target(name: "KeysKit", dependencies: ["PhosphorCore", "SSHKit"], swiftSettings: strict),

        // Palettes, theme import, localization-independent styling.
        .target(name: "ThemeKit", dependencies: ["PhosphorCore"], swiftSettings: strict),

        // Host capability probe and provisioning recipes.
        .target(name: "ProvisionKit", dependencies: ["PhosphorCore", "SSHKit"], swiftSettings: strict),

        // SwiftUI views.
        .target(
            name: "PhosphorUI",
            dependencies: ["PhosphorCore", "VaultKit", "HostsKit", "SSHKit",
                           "DockerKit", "MetricsKit", "KeysKit", "ThemeKit", "ProvisionKit"],
            swiftSettings: strict
        ),

        .executableTarget(name: "Phosphor", dependencies: ["PhosphorUI"], swiftSettings: strict),

        .testTarget(
            name: "PhosphorTests",
            dependencies: ["PhosphorCore", "VaultKit", "HostsKit", "SSHKit",
                           "DockerKit", "MetricsKit", "KeysKit", "ThemeKit", "ProvisionKit"],
            swiftSettings: strict
        ),
    ]
)
