// safari-mcp-bridge/main.swift
import Foundation

// CLI entry point for safari-mcp-bridge.
// Modes:
//   (no flags)   — stdio-to-socket relay for MCP communication
//   --install    — write MCP config to Claude Code + Desktop
//   --uninstall  — remove MCP config from Claude Code + Desktop
//   --status     — print diagnostic info

let args = CommandLine.arguments.dropFirst() // skip executable name
let command = args.first

switch command {
case "--install":
    // Resolve our own path (the bridge binary)
    let bridgePath = ProcessInfo.processInfo.arguments[0]
    let resolvedPath: String
    if let realPath = realpath(bridgePath, nil) {
        resolvedPath = String(cString: realPath)
        free(realPath)
    } else {
        resolvedPath = bridgePath
    }

    let verify = args.contains("--verify")
    let clients = ConfigInstaller.detectClients()

    if clients.isEmpty {
        print("⚠ No Claude clients detected.")
        print("  Install Claude Code (https://claude.ai/download) or Claude Desktop first.")
        // Still install to the default paths in case detection failed
    }

    var configuredClients: [String] = []
    let targets = clients.isEmpty
        ? [("Claude Code CLI", ConfigInstaller.claudeCodeConfigPath)]  // fallback: always write Claude Code config
        : clients

    for (name, path) in targets {
        let result = ConfigInstaller.installConfig(bridgePath: resolvedPath, configPath: path)
        if result.success {
            print("✓ \(name) — configured")
            configuredClients.append(name)
        } else {
            print("✗ \(name) — \(result.message)")
        }
    }

    ConfigInstaller.writeMarkerFile(bridgePath: resolvedPath, clients: configuredClients)

    if verify {
        // Full MCP handshake: connect, initialize, tools/list, report tool count
        if let socketPath = BridgeRelay.findNewestSocket(in: BridgeRelay.socketDirectory) {
            let toolCount = BridgeRelay.verifyConnection(socketPath: socketPath)
            if let count = toolCount {
                print("\n✓ Connection verified — \(count) tools available")
            } else {
                print("\n⚠ Socket exists but verification failed. Restart Claude in Safari.")
            }
        } else {
            print("\n⚠ Config installed, but Claude in Safari is not running. Launch the app to activate.")
        }
    }

    print("\nDone! Restart Claude Code or Claude Desktop to connect.")
    exit(0)
case "--uninstall":
    let paths = [
        ("Claude Code CLI", ConfigInstaller.claudeCodeConfigPath),
        ("Claude Desktop", ConfigInstaller.claudeDesktopConfigPath)
    ]
    for (name, path) in paths {
        let result = ConfigInstaller.uninstallConfig(configPath: path)
        print("\(result.success ? "✓" : "✗") \(name) — \(result.message)")
    }
    ConfigInstaller.removeMarkerFile()
    print("\nDone! MCP config removed.")
    exit(0)
case "--status":
    StatusReporter.printStatus()
    exit(0)
case nil:
    BridgeRelay.run()
default:
    fputs("Unknown flag: \(command!)\nUsage: safari-mcp-bridge [--install | --uninstall | --status]\n", stderr)
    exit(1)
}
