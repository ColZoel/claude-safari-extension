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
    // TODO: Task 4
    print("--install not yet implemented")
    exit(1)
case "--uninstall":
    // TODO: Task 4
    print("--uninstall not yet implemented")
    exit(1)
case "--status":
    // TODO: Task 5
    print("--status not yet implemented")
    exit(1)
case nil:
    // Default: bridge relay mode
    // TODO: Task 3
    print("bridge relay not yet implemented")
    exit(1)
default:
    fputs("Unknown flag: \(command!)\nUsage: safari-mcp-bridge [--install | --uninstall | --status]\n", stderr)
    exit(1)
}
