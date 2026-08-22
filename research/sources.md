# Source ledger

Observed on 2026-08-22. Environment-practice recommendations are limited to
sources published, released, committed, or freshly served since 2026-05-22.

## Official platform and product sources

- [Homebrew Formula Cookbook](https://docs.brew.sh/Formula-Cookbook), observed
  2026-08-22: formula metadata, functional tests, service definitions, and
  `brew audit`.
- [Homebrew tap guide](https://docs.brew.sh/How-to-Create-and-Maintain-a-Tap),
  observed 2026-08-22: one-command direct tap install and tap naming.
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
