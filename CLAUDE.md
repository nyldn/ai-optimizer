# AI Optimizer

@AGENTS.md

Follow `AGENTS.md` as the shared Codex/Claude contract. For any environment
assessment, begin with the read-only repository handshake:

```sh
./bin/ai-optimizer agent-context --json
```

Do not infer repair authority from a diagnostic finding. If the user asked for
changes, make the smallest reversible fix, verify it with the owning tool, and
re-run the handshake before reporting completion.
