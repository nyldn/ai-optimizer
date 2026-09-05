# Changelog

All notable changes are documented here. AI Environment Optimizer follows semantic
versioning.

## 0.3.0 - 2026-09-05

- Detect Claude and Codex desktop bundles separately from standalone PATH CLIs,
  including the verified Codex bundle distributed under the ChatGPT app name.
- Keep missing standalone CLIs informational when the desktop app is detected;
  describe headless automation dependencies and checks that remain in the app.
- Add a separate, redacted manual Claude Desktop MCP inventory and document
  current desktop, CLI, and cloud configuration boundaries.
- Report distinct app copies without executing bundled runtimes or modifying
  provider installations, accounts, connectors, or schedules.

## 0.2.0 - 2026-08-23

- Rename the public project, repository, formula, release archive, and primary
  command to AI Environment Optimizer and `ai-env-optimizer`.
- Preserve `ai-optimizer` as a working command alias and accept existing v0.1
  state, install markers, environment variables, and direct-install roots.
- Keep both existing launchd service labels stable to prevent duplicate jobs,
  while new installs use the canonical state directory and environment prefix.
- Add a Homebrew same-tap formula migration so installed users upgrade without
  uninstalling or losing their opted-in service.
- Add path-free storage inventory for Claude, Codex, Claude-Mem, and product
  state with historical sessions, memories, worktrees, and active state
  protected by code-level classifications.
- Add token-verified, provider-idle, same-filesystem cleanup of allowlisted old
  caches through a recoverable private Trash folder; no scheduled deletion or
  arbitrary path mode exists.
- Add report-only storage health to evening maintenance with a configurable
  10 GiB warning threshold.

## 0.1.8 - 2026-08-23

- Add a read-only `agent-context` handshake with embedded doctor and workspace
  reports, deduplicated priorities, authorization boundaries, and completion
  gates for coding agents.
- Give Codex and Claude Code one shared repository-root operating contract,
  including distinct environment-operator and product-development workflows.
- Document and test the complete agent onboarding and verification loop.

## 0.1.7 - 2026-08-23

- Warn (and therefore fail `--strict`) when a linked skill directory cannot be
  used, while keeping its path out of both human and JSON reports.
- Document Homebrew's native, opt-in 19:30 service as the recommended scheduled
  maintenance path for Homebrew installations.

## 0.1.6 - 2026-08-22

- Keep the configured AI Optimizer executable out of the launchd plist
  entirely; a versioned product-owned launcher embeds its absolute path with
  shell-safe quoting.
- Make launcher identity stable across Homebrew keg target changes and refuse
  drifted or symlinked launcher files.
- Add live-upgrade regression coverage using a Homebrew revision change that
  removes the prior Cellar directory.

## 0.1.5 - 2026-08-22

- Replace the short-lived `/usr/bin/env` launch item with a stable,
  product-owned maintenance launcher under Application Support.
- Keep the exact AI Optimizer executable out of launchd's program arguments so
  it is not the registered launch program. This was superseded by v0.1.6 after
  live evidence showed an executable path in plist environment state was still
  associated with keg replacement.
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
