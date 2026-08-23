# Source ledger

Observed on 2026-08-23. Environment-practice recommendations are limited to
sources published, released, committed, or freshly served since 2026-05-22.

## Official platform and product sources

- [Homebrew Formula Cookbook](https://docs.brew.sh/Formula-Cookbook), observed
  2026-08-22: formula metadata, functional tests, service definitions, and
  `brew audit`.
- [Homebrew tap guide](https://docs.brew.sh/How-to-Create-and-Maintain-a-Tap),
  observed 2026-08-23: one-command direct tap install and tap naming.
- [Homebrew same-tap formula rename implementation](https://github.com/Homebrew/brew/blob/master/Library/Homebrew/tap.rb),
  observed 2026-08-23; the file was changed on 2026-08-07: taps load
  `formula_renames.json` as an old-name to new-name map.
- [Homebrew service name implementation](https://github.com/Homebrew/brew/blob/master/Library/Homebrew/service.rb),
  observed 2026-08-23; the file was changed on 2026-07-31: the public service
  DSL accepts an explicit macOS plist name, allowing a formula rename to retain
  an existing launchd identity.
- [GitHub releases](https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases),
  observed 2026-08-22: tagged releases and immutable uploaded assets.
- [GitHub Actions hardening](https://docs.github.com/en/actions/security-for-github-actions/security-guides/security-hardening-for-github-actions),
  observed 2026-08-22: least privilege and full-SHA action pinning.
- [GitHub artifact attestations](https://docs.github.com/en/actions/concepts/security/artifact-attestations),
  observed 2026-08-22: build provenance and verification.
- [GitHub-hosted runners](https://docs.github.com/en/actions/reference/runners/github-hosted-runners),
  observed 2026-08-22: current `macos-15-intel` and arm64 `macos-15`
  standard runners.
- [Claude Code setup](https://code.claude.com/docs/en/setup), observed
  2026-08-22: macOS 13 minimum, native/Homebrew installation, and
  `claude doctor`.
- [Codex CLI](https://developers.openai.com/codex/cli), observed 2026-08-22:
  standalone/Homebrew installation, permissions, MCP, skills, and
  `codex doctor`.

## Similar-project source

See [public research notes](../docs/research-notes.md) for exact recent commits
and the design decisions they informed.
