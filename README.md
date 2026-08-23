# AI Environment Optimizer

AI Environment Optimizer (`ai-env-optimizer`) is a read-only health check and
narrowly owned maintenance layer
for macOS AI coding environments. It makes Claude Code, Codex, MCP servers,
skills, and Git workspaces understandable without uploading your configuration
or silently changing third-party tools.

Requires macOS 13 or later. Apple Silicon and Intel are both tested.

## Install and run in 30 seconds

Homebrew is the recommended installation path:

```sh
brew install nyldn/tap/ai-env-optimizer
ai-env-optimizer setup
ai-env-optimizer doctor
```

`setup` saves local defaults. It does not change Claude Code, Codex, MCP,
skills, repositories, or launchd unless you explicitly add `--schedule`.

## What you get

- A credential-free `doctor` for macOS, PATH, Claude Code, Codex, optional
  companion tools, MCP configuration health, skills, and product-owned state.
- A `scan` that summarizes Git workspace coverage without reporting repository
  names or file contents.
- A privacy-safe storage inventory with protected-history classifications and
  explicit, token-verified cache cleanup through macOS Trash.
- The same stable findings in readable text or one clean JSON document.
- A shared `agent-context` handshake that tells Codex or Claude Code what to
  inspect, how to prioritize findings, where mutation authority stops, and how
  to verify repairs.
- Opt-in evening diagnostics through one product-owned user launch agent.
- No telemetry and no autonomous code repair.

Example:

```text
AI Environment Optimizer 0.2.0

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
ai-env-optimizer setup [--workspace-root PATH] [--schedule]
ai-env-optimizer doctor [--json] [--strict]
ai-env-optimizer scan [--json] [--strict] [--workspace-root PATH]
ai-env-optimizer agent-context [--json] [--strict] [--workspace-root PATH]
ai-env-optimizer storage [--json] [--strict]
ai-env-optimizer storage cleanup --dry-run [--older-than DAYS] [--min-size MB] [--json]
ai-env-optimizer storage cleanup --apply TOKEN [--older-than DAYS] [--min-size MB] [--json]
ai-env-optimizer report [--json]
ai-env-optimizer schedule [--hour H] [--minute M]
ai-env-optimizer schedule status
ai-env-optimizer unschedule
ai-env-optimizer version
```

The default workspace root is `~/git` when it exists, otherwise the current
directory.

## Upgrading from `ai-optimizer`

Version 0.2 renamed the project and canonical command to `ai-env-optimizer`.
Homebrew migrates the old formula name automatically. The legacy
`ai-optimizer` command remains an exact compatibility alias, and the direct
installer recognizes existing v0.1 install roots, state manifests, environment
variables, and schedules. New environment variables use the
`AI_ENV_OPTIMIZER_*` prefix; existing `AI_OPTIMIZER_*` variables remain
supported.

The direct launchd label `io.github.nyldn.ai-optimizer.daily` and Homebrew
service label `homebrew.mxcl.ai-optimizer` intentionally remain stable so an
upgrade cannot create a duplicate background job.

## Use with Codex or Claude Code

Clone or open this repository, then start either agent from its root. Codex
automatically reads `AGENTS.md`; Claude Code loads `CLAUDE.md`, which imports
the same operating contract. Both are directed to begin with:

```sh
./bin/ai-env-optimizer agent-context --json
```

The handshake combines current doctor and workspace evidence with deduplicated
priorities, remediation, safety rules, and completion checks. It is read-only.
See [Working with Codex and Claude Code](docs/agent-workflow.md) for the schema,
recommended prompt, and repair loop.

For a storage request, both agents are instructed to run the read-only
`./bin/ai-env-optimizer storage --json` inventory after the handshake. They do
not infer cleanup permission from a warning or preview token.

## Storage health and recoverable cleanup

Start with a path-free inventory:

```sh
ai-env-optimizer storage --json
```

It reports aggregate allocated, protected, and potentially reclaimable bytes
for known Claude, Codex, Claude-Mem, and product-owned locations.
Sessions, transcripts, memories, worktrees, and active plugin state are protected
and are never cleanup candidates. Inventory and preview do not write files.

If reclaimable cache data is material, use this exact two-step loop:

```sh
ai-env-optimizer storage cleanup --dry-run --older-than 30 --min-size 100
ai-env-optimizer storage cleanup --apply TOKEN --older-than 30 --min-size 100
```

Preview reports only aggregate source IDs, counts, allocated bytes, and a
candidate-set token. Apply recomputes the candidate set and requires the same
filters and token. It refuses metadata drift, symlinks, running provider apps,
cross-filesystem moves, and destinations it did not create. Eligible files are
moved—not copied or deleted—into one private dated folder in `~/.Trash`, so
they remain recoverable until the user empties Trash. The tool never empties
Trash and has no unattended cleanup mode.

## Evening maintenance

Scheduling is opt-in:

```sh
brew services start nyldn/tap/ai-env-optimizer
```

For Homebrew installs, this is the recommended path. Homebrew creates a
user-level launchd job that runs at 19:30 local time, does not run when first
loaded, and resolves the stable `opt` path across package upgrades. Check or
remove it with:

```sh
brew services info nyldn/tap/ai-env-optimizer
brew services stop nyldn/tap/ai-env-optimizer
```

Do not enable both schedulers. For a checksum-verified direct install, or when
you need a custom time, use AI Environment Optimizer's own scheduler:

```sh
ai-env-optimizer schedule
```

The default is 21:00 local time. AI Environment Optimizer accepts 19:00 through
02:00 and checks the time again when launchd actually starts the process. A Mac
waking later in the morning records `skipped_outside_window` and performs no scan.
Evening maintenance never applies cleanup; it only records aggregate storage
health and a warning when configured storage exceeds the default 10 GiB threshold.
Configuration, receipts, and scheduler logs are stored with owner-only
permissions.
The direct-install launch agent uses an owner-only, product-owned maintenance launcher under
Application Support. Its versioned filename is stable for the configured
executable path, and the Homebrew or direct-install path does not appear in the
launchd plist. Package upgrades therefore leave an already opted-in schedule
registered.

AI Environment Optimizer owns only:

```text
~/Library/LaunchAgents/io.github.nyldn.ai-optimizer.daily.plist
io.github.nyldn.ai-optimizer.daily
```

Remove it with:

```sh
ai-env-optimizer unschedule
```

## Privacy and mutation boundary

`doctor`, `scan`, `agent-context`, `storage`, and storage cleanup preview are
read-only. Reports contain status identifiers, counts, tool versions, and
remediation. They do not contain environment values, command arguments, MCP
endpoints, tokens, workspace names, original storage paths, filenames, or file
contents.

The only mutating commands are:

- `setup`, which writes AI Environment Optimizer configuration;
- `schedule`, which writes and bootstraps the exact launch agent above;
- `unschedule`, which removes that exact launch agent;
- `storage cleanup --apply TOKEN`, which moves only verified allowlisted cache
  candidates to a private folder in the current user's Trash and writes an
  aggregate owner-only receipt.

Graphify, Claude-Mem, and ATK are useful optional companions. AI Environment Optimizer
detects them but does not install, configure, update, or remove them.

See [Privacy](docs/privacy.md) and [Architecture](docs/architecture.md).

## Direct install fallback

Choose Homebrew or direct install. Do not stack both.

The direct path verifies the installer before it runs, then the installer
verifies the release archive before changing live paths:

```sh
VERSION=0.2.0
curl -fLO "https://github.com/nyldn/ai-env-optimizer/releases/download/v$VERSION/install.sh"
curl -fLO "https://github.com/nyldn/ai-env-optimizer/releases/download/v$VERSION/install.sh.sha256"
shasum -a 256 -c install.sh.sha256
bash install.sh --version "$VERSION"
```

Direct installs use `~/.local/share/ai-env-optimizer` and link the command into
`~/.local/bin`. If that directory is not on PATH, the installer prints the
exact zsh line to add.

## Upgrade and uninstall

Homebrew:

```sh
brew upgrade ai-env-optimizer
brew services stop nyldn/tap/ai-env-optimizer
brew uninstall ai-env-optimizer
```

If you used `ai-env-optimizer schedule` instead, run `ai-env-optimizer unschedule`
before uninstalling.

Direct install:

```sh
~/.local/share/ai-env-optimizer/scripts/uninstall.sh
```

Add `--keep-state` to retain AI Environment Optimizer configuration and reports.
Uninstall removes only paths with product provenance.

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
