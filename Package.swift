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
    dependencies: [
        // Готовый эмулятор VT100/xterm: писать свой — это год работы.
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.2.0"),
    ],
    targets: [
        // Shared primitives: no dependencies, no I/O.
        .target(name: "PhosphorCore", swiftSettings: strict),

        // Encrypted profile container and atomic writes.
        .target(name: "VaultKit", dependencies: ["PhosphorCore"], swiftSettings: strict),

        // Biometric gate and Keychain-backed secrets.
        .target(name: "AuthKit", dependencies: ["PhosphorCore", "VaultKit"], swiftSettings: strict),

        // Hosts, groups, tags, ssh_config import, snippets.
        .target(name: "HostsKit", dependencies: ["PhosphorCore"], swiftSettings: strict),

        // Transport abstraction over ssh(1); proxy and jump support.
        .target(name: "SSHKit", dependencies: ["PhosphorCore", "HostsKit"], swiftSettings: strict),

        // Container listing, stats and log streaming over SSH.
        .target(name: "DockerKit", dependencies: ["PhosphorCore"], swiftSettings: strict),

        // /proc snapshot parsing and ring buffers.
        .target(name: "MetricsKit", dependencies: ["PhosphorCore", "SSHKit"], swiftSettings: strict),

        // authorized_keys parsing, fingerprints, safe rewrites.
        .target(name: "KeysKit", dependencies: ["PhosphorCore", "SSHKit"], swiftSettings: strict),

        // Palettes, theme import, localization-independent styling.
        .target(name: "ThemeKit", dependencies: ["PhosphorCore"], swiftSettings: strict),

        // Host capability probe and provisioning recipes.
        .target(name: "ProvisionKit", dependencies: ["PhosphorCore", "SSHKit"], swiftSettings: strict),

        // Terminal emulator wiring: local PTY and remote channels.
        .target(
            name: "TerminalCore",
            dependencies: ["PhosphorCore", "ThemeKit", "HostsKit", "SSHKit",
                           .product(name: "SwiftTerm", package: "SwiftTerm")],
            swiftSettings: strict
        ),

        // Live per-host session: probe, containers, metrics.
        .target(
            name: "SessionKit",
            dependencies: ["PhosphorCore", "SSHKit", "DockerKit", "MetricsKit",
                           "ProvisionKit", "HostsKit", "KeysKit"],
            swiftSettings: strict
        ),

        // MCP tool catalogue, access policy and audit trail.
        .target(
            name: "MCPBridge",
            dependencies: ["PhosphorCore", "HostsKit", "DockerKit", "SessionKit"],
            swiftSettings: strict
        ),

        // SwiftUI views.
        .target(
            name: "PhosphorUI",
            dependencies: [
                "PhosphorCore", "VaultKit", "AuthKit", "HostsKit", "SSHKit", "DockerKit",
                "MetricsKit", "KeysKit", "ThemeKit", "ProvisionKit", "SessionKit",
                "TerminalCore", "MCPBridge",
            ],
            swiftSettings: strict
        ),

        .executableTarget(name: "Phosphor", dependencies: ["PhosphorUI"], swiftSettings: strict),

        .testTarget(
            name: "PhosphorTests",
            dependencies: ["PhosphorCore", "VaultKit", "AuthKit", "HostsKit", "SSHKit",
                           "DockerKit", "MetricsKit", "KeysKit", "ThemeKit",
                           "ProvisionKit", "SessionKit", "MCPBridge", "PhosphorUI"],
            swiftSettings: strict
        ),
    ]
)
