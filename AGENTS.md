# AI Optimizer contributor instructions

AI Optimizer is a public, macOS-only diagnostic and narrowly owned maintenance
CLI for Claude Code, Codex, MCP, skills, and coding workspaces.

## Safety invariants

- `doctor` and `scan` are read-only.
- Never print command arguments, environment values, credentials, MCP endpoint
  values, or workspace file contents.
- Mutating commands may write only AI Optimizer-owned configuration, reports,
  release installation paths, and launchd label
  `io.github.nyldn.ai-optimizer.daily`.
- Never silently edit or upgrade Claude Code, Codex, MCP servers, skills,
  companion tools, or repositories.
- Keep runtime code compatible with `/usr/bin/ruby` 2.6 and standard library
  only.
- Every lifecycle change needs an isolated install/uninstall or
  schedule/unschedule round-trip test.

## Verification

Run all of these before claiming completion:

```sh
/usr/bin/ruby test/test_all.rb
scripts/check-syntax.sh
scripts/build-release.sh
test/install_test.sh
gitleaks git --redact --exit-code 1 .
```
