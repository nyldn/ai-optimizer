# AI Optimizer

AI Optimizer is a read-only health check and narrowly owned maintenance layer
for macOS AI coding environments. It makes Claude Code, Codex, MCP servers,
skills, and Git workspaces understandable without uploading your configuration
or silently changing third-party tools.

Requires macOS 13 or later. Apple Silicon and Intel are both tested.

## Install and run in 30 seconds

Homebrew is the recommended installation path:

```sh
brew install nyldn/tap/ai-optimizer
ai-optimizer setup
ai-optimizer doctor
```

`setup` saves local defaults. It does not change Claude Code, Codex, MCP,
skills, repositories, or launchd unless you explicitly add `--schedule`.

## What you get

- A credential-free `doctor` for macOS, PATH, Claude Code, Codex, optional
  companion tools, MCP configuration health, skills, and AI Optimizer state.
- A `scan` that summarizes Git workspace coverage without reporting repository
  names or file contents.
- The same stable findings in readable text or one clean JSON document.
- Opt-in evening diagnostics through one product-owned user launch agent.
- No telemetry and no autonomous code repair.

Example:

```text
AI Optimizer 0.1.3

[PASS] system.macos - macOS is supported
[PASS] tools.claude.present - Claude Code is available
[WARN] tools.codex.present - Codex is not installed or not on PATH
[INFO] mcp.claude.configured - Claude Code MCP inventory inspected

2 passed, 1 warning
```

Optional tools warn; they do not make the environment fail. A required product
or platform failure exits 1. Use `--strict` when warnings should also fail
automation.

## Commands

```text
ai-optimizer setup [--workspace-root PATH] [--schedule]
ai-optimizer doctor [--json] [--strict]
ai-optimizer scan [--json] [--strict] [--workspace-root PATH]
ai-optimizer report [--json]
ai-optimizer schedule [--hour H] [--minute M]
ai-optimizer schedule status
ai-optimizer unschedule
ai-optimizer version
```

The default workspace root is `~/git` when it exists, otherwise the current
directory.

## Evening maintenance

Scheduling is opt-in:

```sh
ai-optimizer schedule
```

The default is 21:00 local time. AI Optimizer accepts 19:00 through 02:00 and
checks the time again when launchd actually starts the process. A Mac waking
later in the morning records `skipped_outside_window` and performs no scan.
Configuration, receipts, and scheduler logs are stored with owner-only
permissions.

AI Optimizer owns only:

```text
~/Library/LaunchAgents/io.github.nyldn.ai-optimizer.daily.plist
io.github.nyldn.ai-optimizer.daily
```

Remove it with:

```sh
ai-optimizer unschedule
```

## Privacy and mutation boundary

`doctor` and `scan` are read-only. Reports contain status identifiers,
counts, tool versions, and remediation. They do not contain environment values,
command arguments, MCP endpoints, tokens, workspace names, or workspace file
contents.

The only mutating commands are:

- `setup`, which writes AI Optimizer configuration;
- `schedule`, which writes and bootstraps the exact launch agent above;
- `unschedule`, which removes that exact launch agent.

Graphify, Claude-Mem, and ATK are useful optional companions. AI Optimizer
detects them but does not install, configure, update, or remove them.

See [Privacy](docs/privacy.md) and [Architecture](docs/architecture.md).

## Direct install fallback

Choose Homebrew or direct install. Do not stack both.

The direct path verifies the installer before it runs, then the installer
verifies the release archive before changing live paths:

```sh
VERSION=0.1.3
curl -fLO "https://github.com/nyldn/ai-optimizer/releases/download/v$VERSION/install.sh"
curl -fLO "https://github.com/nyldn/ai-optimizer/releases/download/v$VERSION/install.sh.sha256"
shasum -a 256 -c install.sh.sha256
bash install.sh --version "$VERSION"
```

Direct installs use `~/.local/share/ai-optimizer` and link the command into
`~/.local/bin`. If that directory is not on PATH, the installer prints the
exact zsh line to add.

## Upgrade and uninstall

Homebrew:

```sh
brew upgrade ai-optimizer
ai-optimizer unschedule
brew uninstall ai-optimizer
```

Direct install:

```sh
~/.local/share/ai-optimizer/scripts/uninstall.sh
```

Add `--keep-state` to retain AI Optimizer configuration and reports.
Uninstall removes only paths with AI Optimizer provenance.

## Development

Runtime code uses the Ruby standard library and stays compatible with the macOS
system Ruby 2.6:

```sh
/usr/bin/ruby -w test/test_all.rb
scripts/check-syntax.sh
```

Release and install verification:

```sh
scripts/build-release.sh
test/install_test.sh
gitleaks git --redact --exit-code 1 .
```

See [Contributing](CONTRIBUTING.md), [Security](SECURITY.md), and
[Troubleshooting](docs/troubleshooting.md).
