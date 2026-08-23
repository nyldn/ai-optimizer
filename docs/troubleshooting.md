# Troubleshooting

## The command is not found after direct install

The installer links the command into `~/.local/bin`. Add that directory to
zsh once:

```sh
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
exec zsh
```

## JSON consumers fail

Use `ai-env-optimizer doctor --json` or `scan --json`. These write exactly one
JSON document to stdout. Do not merge stderr into stdout.

## A missing tool is a warning

Claude Code, Codex, Graphify, Claude-Mem, and ATK are detected independently.
Missing optional tools warn and exit 0. Use `--strict` when warnings should
fail CI.

## The launch agent is not loaded

For a Homebrew install:

```sh
brew services info nyldn/tap/ai-env-optimizer
brew services restart nyldn/tap/ai-env-optimizer
```

For a direct install or custom schedule:

```sh
ai-env-optimizer schedule status
ai-env-optimizer unschedule
ai-env-optimizer schedule
```

The scheduler is idempotent and reconciles file and launchd state. It owns only
`io.github.nyldn.ai-optimizer.daily`.

Do not run both scheduling modes. Stop the Homebrew service before enabling a
custom AI Environment Optimizer schedule.

## A morning run says skipped

launchd coalesces calendar events missed while a Mac sleeps and may start the
job when the computer wakes. AI Environment Optimizer rechecks local time and records
`skipped_outside_window` instead of scanning outside 19:00-02:00.
