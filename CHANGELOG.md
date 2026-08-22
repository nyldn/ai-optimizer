# Changelog

All notable changes are documented here. AI Optimizer follows semantic
versioning.

## 0.1.2 - 2026-08-22

- Treat skill names intentionally shared across Claude, Codex, and agent roots
  as informational instead of reporting false duplicate warnings.
- Replace destructive PATH cleanup advice with safe guidance to prefer one
  executable and update or remove only a confirmed stale installation.

## 0.1.1 - 2026-08-22

- Move public product state to the collision-resistant macOS Application
  Support name `io.github.nyldn.ai-optimizer`.
- Refuse to claim or uninstall a nonempty data directory without a valid
  AI Optimizer ownership manifest.

## 0.1.0 - 2026-08-22

- Add read-only Claude Code, Codex, MCP, skills, PATH, macOS, and workspace
  diagnostics.
- Add stable human and JSON finding formats with redaction.
- Add explicit setup and product-owned evening launchd scheduling.
- Add deterministic release archives, checksum-verified direct installation,
  and provenance-gated uninstall.
