# Privacy

AI Optimizer 0.1.1 has no telemetry and sends no diagnostic data anywhere.

## Read

The doctor may inspect:

- macOS version and architecture;
- executable presence and version output;
- whether Claude Code and Codex MCP configuration can be parsed;
- counts and basic frontmatter health for known skill directories;
- counts and Git state for direct child workspaces;
- AI Optimizer-owned configuration and launchd state.

## Never report

- environment variable values;
- command arguments;
- tokens, passwords, API keys, or authorization headers;
- MCP server names, commands, arguments, URLs, or query strings;
- repository names, paths, remotes, file names, or file contents.

Paths shown during explicit setup are shortened to `~` for the current home.
Unexpected check failures discard command output and become an `unknown`
finding.

## Write

`doctor` and `scan` do not write. `setup`, `schedule`, and `unschedule`
write or remove only AI Optimizer-owned files and the documented launchd label.
Scheduled maintenance writes one local run receipt after the execution-time
evening guard.

AI Optimizer refuses to claim a nonempty Application Support directory unless
its state manifest already proves product ownership.
