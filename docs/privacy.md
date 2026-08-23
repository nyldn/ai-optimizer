# Privacy

AI Environment Optimizer 0.2.0 has no telemetry and sends no diagnostic data anywhere.

## Read

The doctor may inspect:

- macOS version and architecture;
- executable presence and version output;
- whether Claude Code and Codex MCP configuration can be parsed;
- counts and basic frontmatter health for known skill directories;
- counts and Git state for direct child workspaces;
- AI Environment Optimizer-owned configuration and launchd state.
- aggregate allocated bytes and age buckets for a fixed catalog of AI-related
  storage locations.

## Never report

- environment variable values;
- command arguments;
- tokens, passwords, API keys, or authorization headers;
- MCP server names, commands, arguments, URLs, or query strings;
- repository names, paths, remotes, file names, or file contents.
- storage source paths, original paths or filenames, session content, or
  transcript content.

Paths shown during explicit setup are shortened to `~` for the current home.
Unexpected check failures discard command output and become an `unknown`
finding.

## Write

`doctor`, `scan`, and `agent-context` do not write. Storage inventory and
cleanup preview do not write either.
`setup`, `schedule`, and `unschedule` write or remove only AI Environment
Optimizer-owned files and the documented launchd label.
Scheduled maintenance writes one local run receipt after the execution-time
evening guard. Configuration, receipts, and scheduler logs use owner-only
permissions. Its fixed maintenance launcher is also owner-only and uses only
the shell-quoted absolute executable path written by the explicit `schedule`
command. That path does not appear in the launchd plist.

AI Environment Optimizer refuses to claim a nonempty Application Support directory unless
its state manifest already proves product ownership.

Cleanup apply is the only mutation of third-party storage. It accepts no path,
protects sessions, transcripts, memories, worktrees, plugin state, and VM
bundles, and moves only catalog-allowlisted regenerable caches or bounded
product logs. It requires a fresh preview token, stopped provider processes,
and a same-filesystem move into a new private Trash folder. Its receipt omits
original paths or filenames. AI Environment Optimizer never empties Trash and
scheduled maintenance never invokes cleanup.

Apply revalidates identity metadata immediately before each rename. A
same-user process with concurrent write access could still change a directory
between that check and the rename because Ruby 2.6 has no portable
directory-descriptor-relative rename API. Provider-process refusal, allowlisted
roots, fresh private destinations, and recoverability through Trash bound this
residual race; it is not a protection against a hostile process already
running as the same macOS user.
