# Changelog

All notable changes are documented here. AI Optimizer follows semantic
versioning.

## 0.1.5 - 2026-08-22

- Replace the short-lived `/usr/bin/env` launch item with a stable,
  product-owned maintenance launcher under Application Support.
- Keep the exact AI Optimizer executable out of launchd's program arguments so
  Homebrew keg replacement does not unregister an opted-in schedule.
- Refuse symlinked launcher targets and install the launcher atomically with
  owner-only permissions.

## 0.1.4 - 2026-08-22

- Use immutable `/usr/bin/env` as the launch program. This was superseded by
  v0.1.5 after live Background Task Management evidence showed macOS removed
  the generic `env` launch item.

## 0.1.3 - 2026-08-22

- Pre-create scheduled-maintenance logs with owner-only permissions and repair
  older product-owned log modes without truncating their contents.
- Refuse symlinked log targets before launchd registration.

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
