# Codex Usage Monitor — Agent Guide

## Scope and architecture

- `core/` is the Node.js monitor service and JSON/API logic.
- `macos/` is the native macOS app, built with SwiftUI and AppKit.
- Keep changes narrowly scoped; do not refactor unrelated code.

## Editing rules

- Make macOS UI changes in `macos/Sources/UsageMonitor/main.swift`.
- Do not edit generated files or build outputs: `macos/.build/` and `build/`.
- Preserve the local HTTP contract between the macOS app and `core/monitor.mjs` unless the task explicitly requires changing it.
- Do not commit, tag, or publish changes unless explicitly requested.

## Verification

- Core tests: `npm test`
- Swift package build: `cd macos && swift build -c release`
- Packaged app build: `make build`

Run the smallest relevant verification after a change; report the command and result.
