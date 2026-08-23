# AI Environment Optimizer agent instructions

AI Environment Optimizer is a public, macOS-only diagnostic and narrowly owned
maintenance CLI for Claude Code, Codex, MCP, skills, and coding workspaces.
Codex reads this file automatically. Claude Code receives the same contract
through `CLAUDE.md`.

## Choose the workflow

- Use the **Operator workflow** when the user asks to inspect, configure,
  optimize, maintain, or repair their AI coding environment.
- Use the **Development workflow** when the user asks to change AI Environment
  Optimizer itself.
- If both apply, gather operator evidence first, then develop against a failing
  test without mixing host-specific data into the repository.

## Operator workflow

1. From this repository root, run the read-only handshake:

   ```sh
   ./bin/ai-env-optimizer agent-context --json
   ```

   Add `--workspace-root PATH` only when the user identifies a different
   workspace container. Do not run `setup`, scheduling, package-manager, or
   repair commands merely to gather context.

   Run `./bin/ai-env-optimizer storage --json` only when the user asks about storage
   or an evening receipt already reports a storage warning. Inventory is
   read-only and path-free.

2. Read `overall_status`, `prioritized_actions`, and both embedded reports.
   Treat priorities as:

   - `P0`: required product/platform failure or unknown state;
   - `P1`: non-required failure or unknown state;
   - `P2`: warning that needs review.

3. Preserve the user's authorization boundary:

   - For inspect, explain, review, or status requests, remain read-only.
   - When the user explicitly asks for fixes, investigate each finding at its
     owning source and make the smallest reversible change.
   - Ask before deleting data, creating credentials, authenticating remote MCP
     services, enabling schedules, upgrading unrelated software, or changing
     another repository's behavior.
   - For storage cleanup, first show the aggregate `--dry-run` result.
     Never infer permission to apply cleanup from a preview token. Apply only
     the exact token and filters the user explicitly approved.
   - Sessions, transcripts, memories, worktrees, and active plugin state are
     protected and must never be reclassified as cleanup candidates ad hoc.

4. Never print or commit credentials, environment values, MCP endpoints,
   command arguments from user sessions, workspace names, or workspace file
   contents. AI Environment Optimizer reports are deliberately redacted; do not weaken that
   boundary while investigating.

5. Verify repairs with the affected tool's native doctor or focused test, then
   re-run:

   ```sh
   ./bin/ai-env-optimizer agent-context --json
   ```

   Report exact evidence, remaining findings, changed paths, and rollback
   instructions. Do not claim the environment is healthy solely because a
   command exited successfully.

## Development workflow

1. Read `README.md`, `docs/architecture.md`, and the relevant tests.
2. Preserve these invariants:

   - `doctor`, `scan`, `agent-context`, `storage`, and cleanup preview are read-only.
   - Mutating commands may write only AI Environment Optimizer-owned configuration,
     reports, release installation paths, and launchd label
     `io.github.nyldn.ai-optimizer.daily`.
     This legacy internal label is intentionally stable across the v0.2 rename.
   - Cleanup apply may move only catalog entries marked eligible in code, only
     after token revalidation, and only to the current user's Trash. Scheduled
     maintenance must never invoke cleanup.
   - Never silently edit or upgrade Claude Code, Codex, MCP servers, skills,
     companion tools, or repositories.
   - Keep runtime code compatible with `/usr/bin/ruby` 2.6 and the standard
     library only.
   - Every lifecycle change needs an isolated install/uninstall or
     schedule/unschedule round-trip test.

3. Write a failing regression test before implementation.
4. Run the smallest relevant test while iterating.
5. Before claiming completion, run:

   ```sh
   /usr/bin/ruby -w test/test_all.rb
   scripts/check-syntax.sh
   scripts/build-release.sh
   test/install_test.sh
   gitleaks git --redact --exit-code 1 .
   ```

See `docs/agent-workflow.md` for the handshake schema and integration examples.
