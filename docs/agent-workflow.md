# Working with Codex and Claude Code

AI Environment Optimizer gives coding agents a deterministic, read-only starting point.
The repository's `AGENTS.md` and `CLAUDE.md` route both Codex and Claude Code to
the same command:

```sh
./bin/ai-env-optimizer agent-context --json
```

Use the installed command instead when you are not working from a checkout:

```sh
ai-env-optimizer agent-context --json
```

## What the handshake returns

The single JSON document contains:

- `overall_status`: `healthy`, `review`, or `action_required`;
- `agent_contract`: the read-only boundary, workflow, prohibited behavior, and
  completion gates;
- `prioritized_actions`: deduplicated `P0`, `P1`, and `P2` findings with their
  affected tools and existing remediation;
- `reports.doctor`: current macOS, tool, MCP, skill, and product findings;
- `reports.scan`: the same health evidence plus privacy-preserving workspace
  coverage.

The command does not write configuration, start services, install packages,
authenticate providers, or edit repositories. Its exit behavior matches
`doctor` and `scan`: required failures exit 1, while warnings exit 1 only with
`--strict`.

## Recommended agent loop

```text
read repository instructions
        ↓
run agent-context --json
        ↓
inspect prioritized evidence
        ↓
stay read-only or apply an explicitly requested, reversible repair
        ↓
run focused native verification
        ↓
run agent-context --json again and report remaining findings
```

This deliberately separates diagnosis from mutation. An LLM can understand
what to inspect and how to verify it without receiving blanket authority to
rewrite the host.

## Starting a session

From the repository root, start either agent normally:

```sh
codex
```

or:

```sh
claude
```

A useful first request is:

> Assess this Mac's AI coding environment. Follow the repository agent
> contract, fix only safe and reversible issues I authorized, and report
> anything that needs my decision.

Codex automatically discovers `AGENTS.md`; Claude Code loads `CLAUDE.md`, which
imports the same contract.
