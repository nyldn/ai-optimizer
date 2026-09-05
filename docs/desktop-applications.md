# Desktop applications and CLI limits

AI Environment Optimizer can inspect desktop installations without installing
the Claude or Codex standalone CLI. The optimizer itself is a command-line
tool. Run it in Terminal or through an agent with shell access to this Mac.

## Start from a desktop app

Open this repository as a local Codex project or in Claude Desktop's Code tab
with a local folder. Ask:

> Run `./bin/ai-env-optimizer agent-context --json`. Explain the desktop and
> standalone CLI findings, and identify anything that needs an in-app check.
> Keep the assessment read-only.

Use the installed `ai-env-optimizer` command outside a checkout. If the current
chat cannot execute commands on this Mac, run the command in Terminal and share
its redacted output. A shell in a cloud session or isolated workspace inspects
that environment, not necessarily the Mac running the desktop app.

## What needs the standalone CLI?

| Task | Desktop support | Standalone CLI dependency |
| --- | --- | --- |
| Inspect installed apps and local configuration with this optimizer | Run the optimizer from a host shell or share its report | No provider CLI required |
| Interactive local coding and visual review | Claude Code desktop and Codex desktop support this | No separate PATH CLI required |
| Configure Codex MCP servers | Desktop has an MCP settings UI; local clients share configuration for the same host | CLI is an alternative, not a prerequisite |
| Script Claude with `--print` or machine-readable output | No equivalent interactive desktop command | Claude Code CLI |
| Run Codex in scripts or CI with `codex exec` | Desktop tasks do not provide this shell entry point | Codex CLI |
| Native terminal diagnostics such as `claude doctor` | In-app settings and troubleshooting remain available | The named CLI command needs its standalone CLI |
| Scheduled work | Desktop apps have scheduling features with their own requirements | External CI and shell pipelines need the relevant CLI; optimizer launchd jobs only need the optimizer |
| Verify account, plan, permissions, or connected tools | Check in the selected app session | CLI login or local config alone cannot prove desktop readiness |

The automation distinctions come from the fetched [Claude desktop comparison](https://code.claude.com/docs/en/desktop#coming-from-the-cli)
and [Codex non-interactive mode](https://learn.chatgpt.com/docs/non-interactive-mode).
Claude's [desktop quickstart](https://code.claude.com/docs/en/desktop-quickstart)
explicitly separates desktop installation from installing `claude` for Terminal.

## Configuration boundaries

Claude Desktop contains several modes. Local Code sessions share Claude Code
settings, project memory, skills, and hooks. Chat and Cowork have different
execution and customization boundaries. Current documentation describes both
cloud and device execution for Cowork, so its installed app alone does not
identify where a task runs. Check the selected mode and execution host.
See [Claude desktop](https://code.claude.com/docs/en/desktop) and
[Cowork architecture](https://support.claude.com/en/articles/14479288-claude-cowork-architecture-overview).

The manual macOS Claude Desktop file is
`~/Library/Application Support/Claude/claude_desktop_config.json`. Current local
Code sessions also load those MCP definitions. The standalone CLI does not read
that file directly. Its import command copies configuration and should be an
explicit choice. The optimizer reports this inventory separately from
`~/.claude.json`; it does not add the counts together or infer precedence.
Desktop extensions and remote connectors are not included in the manual count.
See [Claude desktop MCP behavior](https://code.claude.com/docs/en/desktop#mcp-servers-from-the-claude-desktop-chat-app).

Codex desktop, CLI, and IDE clients share MCP configuration for the same host,
normally in `~/.codex/config.toml`. Project configuration, trust, alternate
hosts, profiles, and managed settings can change the effective result.
The desktop UI can add and authenticate MCP servers without a terminal CLI.
See [Codex MCP](https://learn.chatgpt.com/docs/extend/mcp) and
[configuration precedence](https://learn.chatgpt.com/docs/config-file/config-basic).

## What the optimizer verifies

- Known app names in `/Applications` and `~/Applications`, verified against
  bundle IDs, executable presence, and numeric version metadata.
- Distinct copies, with filesystem aliases deduplicated. A duplicate warning
  asks you to inspect the preferred app; it never removes a copy.
- Standalone PATH CLIs independently of desktop installations. App-contained
  runtime executables and links to them are not invoked as CLI diagnostics.
- The top-level manual Claude Desktop MCP server count. Reports omit server
  names, endpoints, commands, environment values, and original file paths.
  Unsafe links, invalid structures, unreadable files, and files over 1 MiB
  produce a warning without exposing their contents.

Bundle detection does not verify code signing, login, running state, feature
entitlement, or connector health. The optimizer does not launch apps, query
Keychain, send prompts, call MCP servers, install extensions, inspect session
contents, or change provider configuration. Custom app names and install
locations are outside this bounded scan and may not be detected.

## Research and version scope

Verified against fetched official pages on 2026-09-05. Search snippets included
older Claude behavior that conflicts with the current page, particularly MCP
sharing. The implementation follows the fetched page and preserves separate
inventory counts so older desktop versions are not assumed to behave the same.

OpenAI's former `developers.openai.com/codex/app` pages now redirect to ChatGPT
desktop documentation. Local bundle metadata confirms `com.openai.codex` can
appear under either `Codex.app` or `ChatGPT.app`. Name alone is insufficient:
the older `com.openai.chat` bundle is not classified as a Codex installation.
See the [current desktop documentation](https://learn.chatgpt.com/docs/app).

The source ledger records these references. Feature availability can change;
verify the installed app's UI before relying on a capability or migrating its
configuration. No minimum app version is inferred from the optimizer's own
macOS 13 requirement.
