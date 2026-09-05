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

## Desktop support, verified 2026-09-05

- [Claude desktop comparison](https://code.claude.com/docs/en/desktop): fetched
  current page, rather than stale search snippets. Local Code configuration,
  desktop MCP loading and precedence, headless CLI limits, and manual checks.
- [Claude desktop quickstart](https://code.claude.com/docs/en/desktop-quickstart):
  desktop works without a separately installed terminal CLI.
- [Claude local MCP](https://support.claude.com/en/articles/10949351-getting-started-with-local-mcp-servers-on-claude-desktop):
  desktop extension setup; manual JSON is not the entire connector inventory.
- [Cowork architecture](https://support.claude.com/en/articles/14479288-claude-cowork-architecture-overview):
  mode and execution location must be checked, not inferred from app presence.
- [OpenAI desktop](https://learn.chatgpt.com/docs/app): current destination of
  the former Codex app documentation URL. Local metadata independently verified
  the `com.openai.codex` bundle ID under Codex and ChatGPT app names.
- [Codex MCP](https://learn.chatgpt.com/docs/extend/mcp): desktop settings UI
  and configuration shared by local clients using the same host.
- [Codex configuration](https://learn.chatgpt.com/docs/config-file/config-basic):
  user, project, profile, system, and managed configuration boundaries.
- [Codex non-interactive mode](https://learn.chatgpt.com/docs/non-interactive-mode):
  `codex exec` for scripts and CI.

## Similar-project source

See [public research notes](../docs/research-notes.md) for exact recent commits
and the design decisions they informed.
