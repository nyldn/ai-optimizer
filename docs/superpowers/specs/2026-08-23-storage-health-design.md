# Storage health and safe cleanup design

## Status

Approved direction for AI Environment Optimizer v0.2. Sessions, transcripts,
memories, worktrees, databases, plugins, and runtime bundles are protected by
default. Scheduled maintenance remains diagnostic only.

## Problem

AI coding tools can accumulate many gigabytes of session history, plugin
copies, application caches, logs, runtime bundles, temporary worktrees, and
generated media. These categories have different value and risk. Treating all
old data as disposable would destroy useful historical evidence; treating all
data as permanent leaves users unable to understand or recover storage.

AI Environment Optimizer needs to answer three questions without exposing
private work:

1. How much allocated storage does each AI-tool category use?
2. Which data is regenerable, historical, active, or merely bounded logs?
3. What can be reclaimed safely, reversibly, and only with explicit approval?

## Considered approaches

### Advisory only

Report storage without providing cleanup. This has the smallest mutation
surface, but leaves users to translate aggregate findings into risky manual
filesystem commands.

### Protected-history hybrid (selected)

Inventory all supported categories, protect historical and active data, and
offer a two-command cleanup only for a narrow allowlist of regenerable data.
Move eligible filesystem entries to the macOS Trash and prefer official native
cleanup commands when a provider exposes them. This balances useful recovery
with auditability and rollback.

### Automatic retention

Delete old caches, logs, or sessions during evening maintenance. This could
recover space without interaction, but age does not prove that data is
unimportant. It also makes a diagnostic schedule destructive. This approach is
rejected.

## Commands and user experience

### Inventory

```text
ai-env-optimizer storage [--json] [--strict]
```

`storage` is read-only. Human output shows allocated size, age buckets,
classification, reclaimability, and any native cleanup capability. JSON uses a
stable schema and the canonical `ai-env-optimizer` product identity.

The report contains source IDs such as `claude.app_cache` and
`codex.sessions`, never absolute paths, filenames, project names, session IDs,
prompts, tool arguments, endpoints, or file contents. `--strict` exits 1 when a
configured storage threshold is exceeded or a supported root cannot be safely
inspected.

### Cleanup preview

```text
ai-env-optimizer storage cleanup --dry-run [--older-than DAYS] [--min-size MB]
```

Cleanup defaults to preview behavior and remains read-only. It reports only
aggregate candidate counts and allocated bytes. It emits a candidate-set token
derived from source IDs, selection options, and `lstat` metadata. Paths are not
encoded in the displayed token.

`--older-than` defaults to 30 days and accepts 1 through 3650 days.
`--min-size` defaults to 100 MB and applies to the aggregate eligible bytes for
each source, not to individual files. This prevents a cache made of many small
files from being overlooked.

### Cleanup apply

```text
ai-env-optimizer storage cleanup --apply TOKEN [--older-than DAYS] [--min-size MB]
```

Apply recomputes the candidate set and refuses to continue unless it exactly
matches the preview token. The options must match the preview. A changed file,
new symlink, provider process, permission error, mount change, or candidate-set
drift invalidates the token and requires a new preview.

Eligible filesystem entries are moved into one dated
`~/.Trash/ai-env-optimizer-<timestamp>` directory. The command does not empty
Trash. It writes an owner-only receipt containing aggregate counts, source IDs,
the Trash folder basename, and the verification result. It never records the
original paths or filenames.

The legacy `ai-optimizer` command alias exposes the same behavior.

## Storage model

Each supported source definition contains:

- a stable public source ID and provider;
- a standard root resolved below the current user's home directory;
- a classification;
- whether inspection may recurse;
- whether cleanup is eligible;
- the provider process that must be stopped for cleanup;
- an optional official native dry-run and apply command.

The initial classifications are:

| Classification | Examples | Initial cleanup policy |
|---|---|---|
| `regenerable` | application caches, code caches, GPU caches | Explicit preview and Trash move only |
| `bounded_logs` | product logs and third-party diagnostic logs | Report; only product-owned logs are initially eligible |
| `historical` | sessions, transcripts, file history, memories | Protected; report only |
| `active` | plugins, marketplaces, VM bundles, databases, worktrees | Protected; report only |

Age is evidence for prioritization, not deletion authority. Session history is
valuable for work continuation, provenance, failure analysis, and future
workflow evaluation. No session, transcript, memory, file-history entry,
database, worktree, plugin, marketplace, or runtime bundle is eligible in the
initial cleanup allowlist.

Claude's native plugin prune preview can be reported as an additional signal.
It is not automatically applied in the initial release. Codex's native archive
and delete commands remain user-directed per-session operations and are never
called by cleanup.

## Measurement and privacy

The scanner uses `lstat` and never follows symlinks. It de-duplicates regular
files by device and inode, then reports allocated bytes from filesystem blocks
rather than apparent file length. Directory metadata is included once.

Age buckets are `0-7`, `8-30`, `31-90`, and `over-90` days. Aggregation occurs
in memory before rendering. A source that changes or becomes unreadable during
inspection returns `unknown`; the report does not silently present a partial
total as complete.

Standard paths remain internal implementation details. Errors are redacted to
stable source IDs and status messages. The storage report follows the existing
rule that environment values, usernames, workspace names, session identifiers,
and command arguments never enter output.

## Components

### `StorageSource`

Immutable definition and validation for one supported category. It resolves a
standard path, enforces home-directory containment, and owns the classification
and cleanup policy.

### `StorageScanner`

Read-only traversal and allocation accounting. It produces per-source
measurements and warnings without exposing filesystem identities.

### `StorageReport`

Human and JSON renderers with deterministic ordering, totals, age buckets,
classification, reclaimability, and exit behavior.

### `CleanupPlanner`

Filters only allowlisted regenerable/product-owned candidates. It validates
age and size options and creates the deterministic candidate-set token without
writing state.

### `CleanupExecutor`

Recomputes and verifies the token, refuses unsafe state, checks that relevant
providers are stopped, moves candidates to Trash without crossing filesystems,
and writes the aggregate receipt. There is no recursive-delete fallback.

## Safety and failure handling

- Inventory and preview never write.
- Evening maintenance may run inventory and record aggregate warnings, but may
  not invoke cleanup.
- Cleanup operates only on source definitions marked eligible in code; command
  arguments cannot add arbitrary paths.
- A symlink at a source root, candidate, ancestor, or Trash destination causes
  refusal.
- Cleanup refuses unrelated or unowned existing Trash destinations and receipt
  paths.
- No cross-volume copy fallback is allowed. A failed move stops the operation,
  reports how many entries were already moved, and preserves them in Trash for
  manual recovery.
- Provider-native cleanup commands must support a dry-run or inventory mode and
  a noninteractive explicit apply mode before integration.
- Cleanup never invokes shell command strings; native tools receive argument
  arrays through the existing timeout runner.
- Reports and receipts are owner-only and use atomic writes.

## Configuration

Default warning thresholds are conservative and affect reporting only. Users
may configure aggregate warning sizes and preview filters. Configuration cannot
make a protected classification eligible or enable unattended cleanup.

Session archival is a future, separate design. Its eventual requirements are
explicit opt-in, pinned-session protection, export verification, encryption or
owner-only cold storage, and confirmation before removing originals.

## Testing and verification

Tests use isolated temporary homes and synthetic allocated files. Required
coverage includes:

- deterministic human/JSON parity and ordering;
- allocated-size accounting, inode de-duplication, and all age buckets;
- no path, filename, project, session, or environment-value leakage;
- symlink, containment, permission, race, and candidate-drift refusal;
- historical and active categories never entering a cleanup plan;
- preview producing zero filesystem writes;
- option mismatch and invalid token refusal;
- successful same-volume Trash move and owner-only receipt;
- partial-move failure retaining already moved entries in Trash;
- scheduled maintenance remaining non-destructive;
- canonical and legacy command/environment compatibility;
- macOS system Ruby 2.6 compatibility on Apple Silicon and Intel CI.

Release verification includes the existing full suite, deterministic archive,
direct-install upgrade round trip, secret scan, Homebrew formula test, and an
independent review of the exact committed artifact.

## Rollout

1. Ship read-only inventory and JSON reporting.
2. Validate classifications against current official Claude Code and Codex
   behavior.
3. Ship preview and explicit Trash-based cleanup for the narrow initial
   allowlist.
4. Observe receipts and false-positive reports before considering more native
   cleanup integrations.
5. Design session archival separately; never broaden cleanup eligibility as an
   incidental change.
