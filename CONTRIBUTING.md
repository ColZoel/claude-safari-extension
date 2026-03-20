# Contributing to Claude in Safari

Thanks for your interest in contributing! This guide covers development setup, project conventions, and how to submit changes.

## Development Setup

### Prerequisites

- macOS 13 Ventura or later
- Xcode 16 or later
- Node.js (for JavaScript tests)
- Safari → Develop → Allow Unsigned Extensions enabled

### Build and Run

```sh
git clone https://github.com/chriscantu/claude-safari-extension.git
cd claude-safari-extension

# Build, launch, and health-check in one step
make dev

# Or build without launching
make build
```

`make dev` builds the app, launches it, creates a stable socket symlink at `/tmp/claude-mcp-browser-bridge-<username>/dev.sock`, and runs a health check.

### Running Tests

```sh
# JavaScript tests
npm test

# Swift tests
make test-swift
```

## Project Layout

See [STRUCTURE.md](STRUCTURE.md) for the full canonical directory layout.

```
ClaudeInSafari/            # macOS app — MCP server, screenshots, file I/O
ClaudeInSafari Extension/  # Safari Web Extension — tool handlers, content scripts
Shared/                    # Constants shared between both targets
docs/specs/                # Feature specifications (written before code)
Tests/                     # Swift and JavaScript tests
```

## Development Workflow

This project follows the principles in [PRINCIPLES.md](PRINCIPLES.md):

1. **Spec first** — write a spec in `docs/specs/` before any implementation
2. **Test first** — write tests before marking a feature complete
3. **One branch per change** — create `fix/...` or `feature/...` branches
4. **Iterative commits** — commit small batches of working code
5. **Structure compliance** — all files must be placed per [STRUCTURE.md](STRUCTURE.md)

### Adding a New Tool

1. Write a spec: `docs/specs/<NNN>-<tool-name>.md`
2. Write tests: `Tests/JS/` and/or `Tests/Swift/`
3. Implement the tool handler in `ClaudeInSafari Extension/Resources/tools/`
4. Register the tool in `tool-registry.js`
5. Add the script to `manifest.json` background scripts
6. Run tests, commit

### Important Build Notes

- **Never run `xcodebuild clean` alone** — always use `make clean` or `make build`
- **Safari caches extension JS** — use `make safari-restart` after changing any JavaScript
- **Swift-only changes** need only `make kill && make build && make run`
- See [docs/debugging.md](docs/debugging.md) for the full troubleshooting guide

## Submitting Changes

1. Fork the repo and create a feature branch
2. Follow the development workflow above
3. Ensure all tests pass (`npm test && make test-swift`)
4. Open a pull request against `main`

## Architecture

For deeper context on how the extension works, see [CLAUDE.md](CLAUDE.md) which documents the architecture, key technical decisions, and Safari-specific quirks.
