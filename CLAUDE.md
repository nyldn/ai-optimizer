# AI Environment Optimizer

@AGENTS.md

Follow `AGENTS.md` as the shared Codex/Claude contract. For any environment
assessment, begin with the read-only repository handshake:

```sh
./bin/ai-env-optimizer agent-context --json
```

Do not infer repair authority from a diagnostic finding. If the user asked for
changes, make the smallest reversible fix, verify it with the owning tool, and
re-run the handshake before reporting completion.

For storage requests, follow the protected preview/apply workflow in
`AGENTS.md`. Start with `./bin/ai-env-optimizer storage --json`; never treat a
preview token as authorization to apply cleanup.
