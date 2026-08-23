# Storage Health and Safe Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship AI Environment Optimizer v0.2.0 with privacy-preserving storage inventory, protected historical sessions, explicit reversible cache cleanup, a safe product rename, Homebrew migration, and a verified local upgrade.

**Architecture:** Add focused storage source, scanner, report, planner, and executor units under `lib/ai_optimizer`. Inventory and cleanup preview remain read-only; apply recomputes an exact candidate token and moves only allowlisted regenerable files to a new owner-only Trash folder. Existing launchd labels and all v0.1 identities remain compatibility surfaces, while the Homebrew formula and public CLI use `ai-env-optimizer`.

**Tech Stack:** macOS system Ruby 2.6 standard library, Minitest, Bash, launchd, Homebrew formula DSL, GitHub Actions, SHA-256 release checksums and attestations.

---

## File structure

New runtime files have one responsibility each:

- `lib/ai_optimizer/storage_source.rb`: immutable source definition and safe path resolution.
- `lib/ai_optimizer/storage_catalog.rb`: non-overlapping supported Claude, Codex, Claude-Mem, and product-owned categories.
- `lib/ai_optimizer/storage_scanner.rb`: read-only allocated-byte and age-bucket accounting.
- `lib/ai_optimizer/storage_report.rb`: deterministic human and JSON rendering.
- `lib/ai_optimizer/cleanup_planner.rb`: allowlist filtering and candidate-token generation.
- `lib/ai_optimizer/cleanup_executor.rb`: token verification, process guard, Trash moves, and receipt.

Tests mirror each runtime unit. Existing CLI, config, maintenance, installer,
documentation, workflow, and Homebrew formula files change only where they own
integration behavior.

### Task 1: Close the v0.2 rename release gates

**Files:**
- Modify: `test/install_test.sh`
- Modify: `install.sh`
- Modify: `lib/ai_optimizer/report.rb`
- Modify: `lib/ai_optimizer/maintenance.rb`
- Modify: `test/report_test.rb`
- Create: `test/maintenance_test.rb`

- [ ] **Step 1: Add a second-run legacy upgrade regression**

After the existing legacy-root upgrade assertions in `test/install_test.sh`, run
the same v0.2 installer again without a prefix and assert it continues using the
legacy root:

```bash
env HOME="$LEGACY_HOME" \
  AI_ENV_OPTIMIZER_RELEASE_BASE="file://$DIST_DIR" \
  PATH="/usr/bin:/bin" \
  /bin/bash "$ROOT_DIR/install.sh" --version "$VERSION" >/dev/null

[ ! -e "$LEGACY_HOME/.local/share/ai-env-optimizer" ]
[ -f "$LEGACY_ROOT/.ai-env-optimizer-install" ]
[ "$("$LEGACY_BIN_DIR/ai-env-optimizer" version)" = "ai-env-optimizer $VERSION" ]
```

- [ ] **Step 2: Run the round trip and observe the failure**

Run:

```bash
rtk test/install_test.sh
```

Expected: FAIL when the second invocation selects the canonical root and
refuses the legacy-root command links.

- [ ] **Step 3: Make legacy-root discovery idempotent**

Replace the legacy selection condition in `install.sh` with:

```bash
elif [ -f "$LEGACY_INSTALL_ROOT/.ai-env-optimizer-install" ] ||
     [ -f "$LEGACY_INSTALL_ROOT/.ai-optimizer-install" ]; then
  INSTALL_ROOT="$LEGACY_INSTALL_ROOT"
```

- [ ] **Step 4: Add compatibility metadata to every JSON document**

In `AIOptimizer::Report#to_h` and `Maintenance#base_receipt`, add:

```ruby
compatibility: { legacy_names: ["ai-optimizer"] }
```

Use the string key form in `Maintenance`:

```ruby
"compatibility" => { "legacy_names" => ["ai-optimizer"] }
```

Add assertions that doctor/scan reports and scheduled receipts carry this
signal. Create `test/maintenance_test.rb` with a fixed clock, temporary data
directory, and a passing empty `Report`.

- [ ] **Step 5: Verify and commit**

Run:

```bash
rtk /usr/bin/ruby -w test/test_all.rb
rtk scripts/check-syntax.sh
rtk test/install_test.sh
```

Expected: all tests and both installer passes succeed.

Commit:

```bash
rtk git add install.sh test/install_test.sh lib/ai_optimizer/report.rb lib/ai_optimizer/maintenance.rb test/report_test.rb test/maintenance_test.rb
rtk git commit -m "fix: make rename migration idempotent"
```

### Task 2: Define storage sources and protected classifications

**Files:**
- Create: `lib/ai_optimizer/storage_source.rb`
- Create: `lib/ai_optimizer/storage_catalog.rb`
- Create: `test/storage_source_test.rb`
- Modify: `lib/ai_optimizer.rb`

- [ ] **Step 1: Write source-resolution tests**

Cover canonical resolution, home containment, supported classifications, unique
IDs, non-overlapping catalog paths, and the initial cleanup allowlist:

```ruby
def test_historical_sources_are_never_cleanup_eligible
  catalog = AIOptimizer::StorageCatalog.new(home: @home, data_dir: @data_dir)
  protected_sources = catalog.sources.select do |source|
    %w[historical active].include?(source.classification)
  end

  refute_empty protected_sources
  assert protected_sources.none?(&:cleanup_eligible?)
end

def test_source_refuses_parent_traversal
  assert_raises(AIOptimizer::OwnershipError) do
    AIOptimizer::StorageSource.new(
      id: "bad.source", provider: "test", base: :home,
      components: ["..", "outside"], classification: "regenerable",
      cleanup_eligible: true
    ).resolve(home: @home, data_dir: @data_dir)
  end
end
```

- [ ] **Step 2: Run the test and observe missing classes**

Run:

```bash
rtk /usr/bin/ruby -w test/storage_source_test.rb
```

Expected: FAIL with an uninitialized `StorageSource` constant.

- [ ] **Step 3: Implement `StorageSource`**

Create an immutable object with this public contract:

```ruby
module AIOptimizer
  class StorageSource
    CLASSIFICATIONS = %w[regenerable bounded_logs historical active].freeze

    attr_reader :id, :provider, :base, :components, :classification,
                :process_names

    def initialize(id:, provider:, base:, components:, classification:,
                   cleanup_eligible:, process_names: [])
      raise ArgumentError, "invalid source id" unless id.match?(/\A[a-z0-9_.]+\z/)
      raise ArgumentError, "invalid classification" unless CLASSIFICATIONS.include?(classification)
      raise ArgumentError, "invalid base" unless %i[home application_support data_dir].include?(base)
      raise OwnershipError, "unsafe storage component" if components.any? { |item| item.empty? || item == ".." || item.include?(File::SEPARATOR) }
      raise ArgumentError, "protected storage cannot be cleanup eligible" if cleanup_eligible && %w[historical active].include?(classification)

      @id = id.freeze
      @provider = provider.freeze
      @base = base
      @components = components.map(&:dup).map(&:freeze).freeze
      @classification = classification.freeze
      @cleanup_eligible = cleanup_eligible
      @process_names = process_names.map(&:dup).map(&:freeze).freeze
      freeze
    end

    def cleanup_eligible?
      @cleanup_eligible
    end

    def resolve(home:, data_dir:)
      root = case base
             when :home then File.expand_path(home)
             when :application_support then File.join(File.expand_path(home), "Library", "Application Support")
             when :data_dir then File.expand_path(data_dir)
             end
      path = File.expand_path(File.join(root, *components))
      prefix = root.end_with?(File::SEPARATOR) ? root : root + File::SEPARATOR
      raise OwnershipError, "storage source escapes its base" unless path.start_with?(prefix)

      path
    end
  end
end
```

- [ ] **Step 4: Implement the non-overlapping catalog**

`StorageCatalog#sources` returns definitions for these source IDs:

```ruby
DEFINITIONS = [
  ["claude.projects", "claude", :home, [".claude", "projects"], "historical", false, []],
  ["claude.plugin_cache", "claude", :home, [".claude", "plugins", "cache"], "active", false, []],
  ["claude.marketplaces", "claude", :home, [".claude", "plugins", "marketplaces"], "active", false, []],
  ["claude.app_cache", "claude", :application_support, ["Claude", "Cache"], "regenerable", true, ["Claude"]],
  ["claude.code_cache", "claude", :application_support, ["Claude", "Code Cache"], "regenerable", true, ["Claude"]],
  ["claude.gpu_cache", "claude", :application_support, ["Claude", "GPUCache"], "regenerable", true, ["Claude"]],
  ["claude.local_sessions", "claude", :application_support, ["Claude", "local-agent-mode-sessions"], "historical", false, []],
  ["claude.vm_bundles", "claude", :application_support, ["Claude", "vm_bundles"], "active", false, []],
  ["codex.sessions", "codex", :home, [".codex", "sessions"], "historical", false, []],
  ["codex.archived_sessions", "codex", :home, [".codex", "archived_sessions"], "historical", false, []],
  ["codex.plugins", "codex", :home, [".codex", "plugins"], "active", false, []],
  ["codex.worktrees", "codex", :home, [".codex", "worktrees"], "active", false, []],
  ["codex.cache", "codex", :home, [".codex", "cache"], "regenerable", true, ["Codex"]],
  ["claude_mem.index", "claude-mem", :home, [".claude-mem", "chroma"], "historical", false, []],
  ["claude_mem.database", "claude-mem", :home, [".claude-mem", "claude-mem.db"], "historical", false, []],
  ["claude_mem.logs", "claude-mem", :home, [".claude-mem", "logs"], "bounded_logs", false, []],
  ["product.logs", "ai-env-optimizer", :data_dir, ["logs"], "bounded_logs", true, []]
].freeze
```

Build each `StorageSource`, reject duplicate IDs, and reject one resolved source
being an ancestor of another.

- [ ] **Step 5: Wire requires, verify, and commit**

Require source and catalog before scanner/report integration in
`lib/ai_optimizer.rb`. Run the focused and full tests, then commit:

```bash
rtk /usr/bin/ruby -w test/storage_source_test.rb
rtk /usr/bin/ruby -w test/test_all.rb
rtk git add lib/ai_optimizer.rb lib/ai_optimizer/storage_source.rb lib/ai_optimizer/storage_catalog.rb test/storage_source_test.rb
rtk git commit -m "feat: define protected storage catalog"
```

### Task 3: Add read-only allocation scanning

**Files:**
- Create: `lib/ai_optimizer/storage_scanner.rb`
- Create: `test/storage_scanner_test.rb`
- Modify: `lib/ai_optimizer.rb`

- [ ] **Step 1: Write failing scanner tests**

Create synthetic files with fixed mtimes. Assert allocated bytes are positive,
age buckets partition the total, hard links count once, missing roots return
`absent`, and a symlinked source returns `unknown` without following it:

```ruby
measurement = AIOptimizer::StorageScanner.new(
  sources: [source], home: home, data_dir: data_dir,
  clock: -> { Time.utc(2026, 8, 23) }
).scan.first

assert_equal "complete", measurement.fetch("status")
assert_equal measurement.fetch("allocated_bytes"), measurement.fetch("age_buckets").values.sum
refute measurement.key?("path")
```

- [ ] **Step 2: Run the focused test and observe the missing scanner**

```bash
rtk /usr/bin/ruby -w test/storage_scanner_test.rb
```

Expected: FAIL with an uninitialized `StorageScanner` constant.

- [ ] **Step 3: Implement traversal and de-duplication**

Use `Find.find`, `File.lstat`, and a `Set` of `[stat.dev, stat.ino]`. Never call
`File.realpath` during traversal and never descend into symlinks:

```ruby
AGE_BUCKETS = {
  "0_7_days" => 0..7,
  "8_30_days" => 8..30,
  "31_90_days" => 31..90,
  "over_90_days" => 91..Float::INFINITY
}.freeze

def allocated_bytes(stat)
  blocks = stat.respond_to?(:blocks) ? stat.blocks : nil
  blocks ? blocks * 512 : stat.size
end

def bucket_for(stat)
  days = [((@clock.call - stat.mtime) / 86_400).floor, 0].max
  AGE_BUCKETS.find { |_name, range| range.cover?(days) }.first
end
```

Return frozen hashes containing only `id`, `provider`, `classification`,
`cleanup_eligible`, `status`, `allocated_bytes`, `file_count`, `directory_count`,
and the four age buckets. Rescue filesystem errors per source and return
`status: "unknown"` with zero totals.

- [ ] **Step 4: Verify privacy and performance fixtures**

Assert serialized measurements do not include the temporary home, child names,
or symlink target. Add a fixture with 10,000 empty files and assert completion
without changing any mtime or content.

- [ ] **Step 5: Verify and commit**

```bash
rtk /usr/bin/ruby -w test/storage_scanner_test.rb
rtk /usr/bin/ruby -w test/test_all.rb
rtk git add lib/ai_optimizer.rb lib/ai_optimizer/storage_scanner.rb test/storage_scanner_test.rb
rtk git commit -m "feat: scan AI storage without following links"
```

### Task 4: Expose deterministic storage reports in the CLI

**Files:**
- Create: `lib/ai_optimizer/storage_report.rb`
- Create: `test/storage_report_test.rb`
- Modify: `lib/ai_optimizer.rb`
- Modify: `lib/ai_optimizer/cli.rb`
- Modify: `test/cli_test.rb`

- [ ] **Step 1: Write failing report and CLI tests**

Assert canonical identity, compatibility metadata, deterministic source order,
aggregate totals, protected labels, no paths, one JSON document, and `--strict`
exit behavior:

```ruby
payload = JSON.parse(stdout)
assert_equal "ai-env-optimizer", payload.fetch("product")
assert_includes payload.fetch("compatibility").fetch("legacy_names"), "ai-optimizer"
assert payload.fetch("sources").all? { |item| !item.key?("path") }
assert_equal payload.fetch("summary").fetch("allocated_bytes"),
             payload.fetch("sources").sum { |item| item.fetch("allocated_bytes") }
```

- [ ] **Step 2: Run tests and observe missing command/report failures**

```bash
rtk /usr/bin/ruby -w test/storage_report_test.rb
rtk /usr/bin/ruby -w test/cli_test.rb
```

Expected: FAIL because `storage` is unknown and `StorageReport` is undefined.

- [ ] **Step 3: Implement `StorageReport`**

Use schema version 1 and this top-level shape:

```ruby
{
  schema_version: 1,
  product: "ai-env-optimizer",
  compatibility: { legacy_names: ["ai-optimizer"] },
  version: VERSION,
  generated_at: generated_at.iso8601,
  summary: {
    allocated_bytes: complete.sum { |item| item.fetch("allocated_bytes") },
    reclaimable_bytes: eligible.sum { |item| item.fetch("allocated_bytes") },
    protected_bytes: protected.sum { |item| item.fetch("allocated_bytes") },
    unknown_sources: measurements.count { |item| item.fetch("status") == "unknown" }
  },
  sources: measurements.sort_by { |item| item.fetch("id") }
}
```

Human output formats bytes with binary units, labels each source as
`reclaimable`, `protected`, `absent`, or `unknown`, and never renders paths.
`exit_code(strict:)` returns 1 for unknown sources, and under strict mode also
returns 1 when allocated bytes exceed the configured warning threshold.

- [ ] **Step 4: Add `storage` CLI routing**

Extend help and dispatch with:

```ruby
when "storage"
  run_storage(args)
```

`run_storage` parses `--json` and `--strict`, constructs `StorageCatalog` and
`StorageScanner` using `Dir.home` and `data_dir`, renders one report, and returns
its exit code. Reject cleanup subcommands until Tasks 5 and 6 add them.

- [ ] **Step 5: Verify and commit**

```bash
rtk /usr/bin/ruby -w test/storage_report_test.rb
rtk /usr/bin/ruby -w test/cli_test.rb
rtk /usr/bin/ruby -w test/test_all.rb
rtk git add lib/ai_optimizer.rb lib/ai_optimizer/storage_report.rb lib/ai_optimizer/cli.rb test/storage_report_test.rb test/cli_test.rb
rtk git commit -m "feat: add privacy-safe storage inventory"
```

### Task 5: Build a read-only cleanup planner

**Files:**
- Create: `lib/ai_optimizer/cleanup_planner.rb`
- Create: `test/cleanup_planner_test.rb`
- Modify: `lib/ai_optimizer.rb`
- Modify: `lib/ai_optimizer/cli.rb`
- Modify: `test/cli_test.rb`

- [ ] **Step 1: Write failing eligibility and token tests**

Cover the 30-day and 100-MB defaults, option bounds, source-level minimum size,
protected-category exclusion, symlink refusal, deterministic tokens, token
change after metadata drift, and path-free serialization:

```ruby
plan = planner.preview(older_than_days: 30, min_size_mb: 100)
assert plan.fetch("sources").all? { |item| item.fetch("cleanup_eligible") }
refute_includes JSON.generate(plan), home
assert_match(/\A[0-9a-f]{64}\z/, plan.fetch("token"))
```

- [ ] **Step 2: Run the test and observe the missing planner**

```bash
rtk /usr/bin/ruby -w test/cleanup_planner_test.rb
```

Expected: FAIL with an uninitialized `CleanupPlanner` constant.

- [ ] **Step 3: Implement candidate enumeration**

Only sources with `cleanup_eligible?` may be traversed. Use `lstat`; include
regular files older than the cutoff; never include symlinks, sockets, devices,
historical sources, or active sources. Keep full candidate paths private in an
internal `Plan` object while `to_h` returns only source IDs, counts, bytes,
options, and token.

Build the token from a sorted JSON array containing source ID, relative path,
device, inode, mode, size, blocks, and integer mtime:

```ruby
token = Digest::SHA256.hexdigest(JSON.generate(token_rows.sort))
```

Validate `older_than_days` in `1..3650` and `min_size_mb` as a positive integer.
Drop an entire source when its aggregate candidate bytes are below the minimum.

- [ ] **Step 4: Add CLI preview**

Route `storage cleanup` with no apply option, or with `--dry-run`, to the same
read-only preview. Parse `--older-than DAYS`, `--min-size MB`, and `--json`.
Human output prints aggregate counts/bytes and the exact follow-up command with
the token and repeated options.

- [ ] **Step 5: Prove preview writes nothing**

Snapshot all temporary-home paths, modes, mtimes, and contents before and after
both human and JSON previews. Assert the snapshots are identical and no product
data directory was created.

- [ ] **Step 6: Verify and commit**

```bash
rtk /usr/bin/ruby -w test/cleanup_planner_test.rb
rtk /usr/bin/ruby -w test/cli_test.rb
rtk /usr/bin/ruby -w test/test_all.rb
rtk git add lib/ai_optimizer.rb lib/ai_optimizer/cleanup_planner.rb lib/ai_optimizer/cli.rb test/cleanup_planner_test.rb test/cli_test.rb
rtk git commit -m "feat: preview allowlisted storage cleanup"
```

### Task 6: Apply verified cleanup through macOS Trash

**Files:**
- Create: `lib/ai_optimizer/cleanup_executor.rb`
- Create: `test/cleanup_executor_test.rb`
- Modify: `lib/ai_optimizer.rb`
- Modify: `lib/ai_optimizer/cli.rb`
- Modify: `test/cli_test.rb`

- [ ] **Step 1: Write failing executor tests**

Use a temporary Trash root and injected process guard. Cover successful moves,
token mismatch, metadata drift, provider-running refusal, symlinked root,
symlinked candidate, existing destination, cross-device refusal, partial move,
owner-only receipt, and protected sources never moving.

```ruby
result = executor.apply(plan.token)
assert_equal "moved_to_trash", result.fetch("status")
assert_equal 0o700, File.stat(result.fetch("trash_path_for_test")).mode & 0o777
assert File.file?(File.join(data_dir, "reports", "latest-cleanup.json"))
refute File.exist?(original_file)
```

The test-only result may expose `trash_path_for_test`; public renderers must
strip it.

- [ ] **Step 2: Run the test and observe the missing executor**

```bash
rtk /usr/bin/ruby -w test/cleanup_executor_test.rb
```

Expected: FAIL with an uninitialized `CleanupExecutor` constant.

- [ ] **Step 3: Implement preflight and same-volume checks**

`CleanupExecutor` receives a planner, config, Trash root, clock, and process
guard. Before any move it:

```ruby
fresh = planner.preview(
  older_than_days: plan.older_than_days,
  min_size_mb: plan.min_size_mb
)
raise UsageError, "cleanup preview expired; run --dry-run again" unless secure_equal(fresh.token, supplied_token)
raise OwnershipError, "Trash root must not be a symlink" if File.symlink?(trash_root)
raise InternalError, "close the affected AI application before cleanup" if running_provider?
raise OwnershipError, "cleanup cannot cross filesystems" unless File.stat(source_root).dev == File.stat(trash_root).dev
```

Implement constant-time token comparison without ActiveSupport.

- [ ] **Step 4: Implement recoverable moves and receipt**

Create `ai-env-optimizer-YYYYMMDDTHHMMSSZ-<token-prefix>` under Trash with mode
0700 using `Dir.mkdir`, refusing any pre-existing entry. Preserve relative
structure below source-ID directories and move with `File.rename`; do not copy
or recursively delete. Stop on the first error and leave completed moves in
Trash.

Write `reports/latest-cleanup.json` through `Config#atomic_write` with mode 0600:

```ruby
{
  "schema_version" => 1,
  "product" => "ai-env-optimizer",
  "compatibility" => { "legacy_names" => ["ai-optimizer"] },
  "status" => status,
  "generated_at" => clock.call.utc.iso8601,
  "token" => token,
  "trash_folder" => File.basename(destination),
  "moved_files" => moved_count,
  "moved_bytes" => moved_bytes,
  "sources" => moved_source_ids.sort
}
```

- [ ] **Step 5: Add explicit CLI apply**

Parse `--apply TOKEN` only under `storage cleanup`. Require exactly 64 lowercase
hex characters. Reuse preview filters, initialize or validate product-owned
state before moving, invoke the executor, and render only aggregate receipt
fields. No `--force`, arbitrary path, or scheduled apply mode exists.

- [ ] **Step 6: Verify and commit**

```bash
rtk /usr/bin/ruby -w test/cleanup_executor_test.rb
rtk /usr/bin/ruby -w test/cli_test.rb
rtk /usr/bin/ruby -w test/test_all.rb
rtk git add lib/ai_optimizer.rb lib/ai_optimizer/cleanup_executor.rb lib/ai_optimizer/cli.rb test/cleanup_executor_test.rb test/cli_test.rb
rtk git commit -m "feat: move verified cache cleanup to Trash"
```

### Task 7: Add non-destructive evening storage health

**Files:**
- Modify: `lib/ai_optimizer/config.rb`
- Modify: `lib/ai_optimizer/maintenance.rb`
- Modify: `lib/ai_optimizer/cli.rb`
- Modify: `test/config_test.rb`
- Modify: `test/maintenance_test.rb`

- [ ] **Step 1: Write failing configuration and maintenance tests**

Assert defaults contain a 10-GiB report-only threshold and scheduled maintenance
records aggregate storage health without calling planner or executor:

```ruby
assert_equal 10 * 1024 * 1024 * 1024,
             config.defaults.fetch("storage").fetch("warning_bytes")

receipt = maintenance.run
assert_equal 12_000_000_000, receipt.fetch("storage").fetch("allocated_bytes")
assert_equal "warning", receipt.fetch("storage").fetch("status")
assert_equal 0, cleanup_calls
```

- [ ] **Step 2: Run tests and observe missing storage receipt behavior**

```bash
rtk /usr/bin/ruby -w test/config_test.rb
rtk /usr/bin/ruby -w test/maintenance_test.rb
```

Expected: FAIL because the default and receipt field are absent.

- [ ] **Step 3: Add the report-only threshold**

Extend `Config#defaults` with:

```ruby
"storage" => { "warning_bytes" => 10 * 1024 * 1024 * 1024 }
```

Validate that a configured threshold is an integer greater than zero before use;
fall back to the default in read-only commands when existing configuration is
invalid.

- [ ] **Step 4: Inject storage inventory into maintenance**

Add an optional `storage:` callable to `Maintenance#initialize`. During an
inside-window run, call it after the doctor and merge only:

```ruby
"storage" => {
  "status" => allocated_bytes >= warning_bytes ? "warning" : "healthy",
  "allocated_bytes" => allocated_bytes,
  "protected_bytes" => protected_bytes,
  "reclaimable_bytes" => reclaimable_bytes,
  "unknown_sources" => unknown_sources
}
```

Outside the evening window, do not scan storage. Never instantiate
`CleanupPlanner` or `CleanupExecutor` from maintenance.

- [ ] **Step 5: Wire the CLI, verify, and commit**

Pass a lambda that builds the catalog, scanner, and report into `Maintenance`
from `CLI#run_maintenance`. Run:

```bash
rtk /usr/bin/ruby -w test/config_test.rb
rtk /usr/bin/ruby -w test/maintenance_test.rb
rtk /usr/bin/ruby -w test/test_all.rb
rtk git add lib/ai_optimizer/config.rb lib/ai_optimizer/maintenance.rb lib/ai_optimizer/cli.rb test/config_test.rb test/maintenance_test.rb
rtk git commit -m "feat: report storage health in evening maintenance"
```

### Task 8: Document and independently review the complete public experience

**Files:**
- Modify: `README.md`
- Modify: `AGENTS.md`
- Modify: `CLAUDE.md`
- Modify: `docs/agent-workflow.md`
- Modify: `docs/architecture.md`
- Modify: `docs/privacy.md`
- Modify: `docs/troubleshooting.md`
- Modify: `CHANGELOG.md`
- Modify: `test/script_test.rb`

- [ ] **Step 1: Add failing documentation contract tests**

Assert the docs include the canonical inventory, preview, and apply commands;
state that sessions are protected; state that evening maintenance never cleans;
and name the Trash rollback location without using a machine-specific path.

- [ ] **Step 2: Run the documentation test and observe failure**

```bash
rtk /usr/bin/ruby -w test/script_test.rb
```

Expected: FAIL because storage commands are not yet documented.

- [ ] **Step 3: Update public documentation**

Document this exact safe loop:

```bash
ai-env-optimizer storage --json
ai-env-optimizer storage cleanup --dry-run --older-than 30 --min-size 100
ai-env-optimizer storage cleanup --apply TOKEN --older-than 30 --min-size 100
```

Explain classifications, privacy, process-close refusal, token drift, Trash
recovery, protected sessions, and the absence of unattended deletion. Add
`storage --json` to the agent workflow only when a user asks about storage or
the evening receipt reports a warning.

- [ ] **Step 4: Run real Codex and Claude onboarding checks**

From the repository root, run fresh non-persistent read-only sessions and ask
each agent what command it would run first for a storage request. Expected: both
select `./bin/ai-env-optimizer storage --json`, describe it as read-only, and do
not propose deletion without preview and apply authorization.

- [ ] **Step 5: Run Fable 5 release review**

Ask Claude Fable 5 to review the exact commit for privacy leakage, hard-link
accounting, symlink/race handling, session protection, preview/apply parity,
installer rerun compatibility, and scheduled non-deletion. Require PASS before
release.

- [ ] **Step 6: Verify and commit**

```bash
rtk /usr/bin/ruby -w test/test_all.rb
rtk scripts/check-syntax.sh
rtk git diff --check
rtk git add README.md AGENTS.md CLAUDE.md CHANGELOG.md docs test/script_test.rb
rtk git commit -m "docs: explain protected storage optimization"
```

### Task 9: Complete GitHub, Homebrew, release, and local migration

**Files:**
- Modify in a sibling Homebrew tap checkout: `Formula/ai-optimizer.rb` (rename to `Formula/ai-env-optimizer.rb`)
- Create in the sibling Homebrew tap checkout: `formula_renames.json`
- Modify in the sibling Homebrew tap checkout: `.github/workflows/ci.yml`
- Modify in the sibling Homebrew tap checkout: `README.md`
- Update external repository name: `nyldn/ai-optimizer` to `nyldn/ai-env-optimizer`

- [ ] **Step 1: Run the complete local public-repository gate**

```bash
rtk /usr/bin/ruby -w test/test_all.rb
rtk scripts/check-syntax.sh
rtk zsh -lc 'set -euo pipefail
task_tmp="$(mktemp -d "${TMPDIR:-/tmp}/ai-env-final.XXXXXX")"
trap '\''rm -rf "$task_tmp"'\'' EXIT
AI_ENV_OPTIMIZER_DIST_DIR="$task_tmp/a" scripts/build-release.sh
AI_ENV_OPTIMIZER_DIST_DIR="$task_tmp/b" scripts/build-release.sh
cmp "$task_tmp/a/ai-env-optimizer-0.2.0.tar.gz" "$task_tmp/b/ai-env-optimizer-0.2.0.tar.gz"
AI_ENV_OPTIMIZER_DIST_DIR="$task_tmp/a" test/install_test.sh'
rtk gitleaks git --redact --exit-code 1 .
```

Expected: full suite, syntax, deterministic archive, fresh install, two-pass
legacy upgrade, uninstall, and secret scan all pass.

- [ ] **Step 2: Rename the public GitHub repository and update the local remote**

Verify there are no open conflicting pull requests, rename through the GitHub
API, then set `origin` to `https://github.com/nyldn/ai-env-optimizer.git`.
Confirm the old URL redirects and the new default branch is `main`.

- [ ] **Step 3: Merge through a reviewed pull request**

Push the feature branch, open a PR summarizing mutation and privacy boundaries,
wait for both architecture jobs and review threads, address findings, merge,
and verify exact-main CI on the resulting main SHA.

- [ ] **Step 4: Publish and verify v0.2.0**

Tag the exact verified main SHA, wait for the release workflow, verify the
GitHub attestation, independently download all four assets, check SHA-256, and
run the downloaded archive's full tests plus install round trip.

- [ ] **Step 5: Implement the Homebrew rename with a stable service label**

Compute the release digest with `shasum -a 256
ai-env-optimizer-0.2.0.tar.gz`, validate it as exactly 64 lowercase hex
characters, and write that exact value into the formula's mandatory `sha256`
field. Create `Formula/ai-env-optimizer.rb` with this remaining content:

```ruby
class AiEnvOptimizer < Formula
  desc "macOS health, storage, and maintenance CLI for AI coding environments"
  homepage "https://github.com/nyldn/ai-env-optimizer"
  url "https://github.com/nyldn/ai-env-optimizer/releases/download/v0.2.0/ai-env-optimizer-0.2.0.tar.gz"
  license "MIT"

  depends_on macos: :ventura
  depends_on "ruby"

  def install
    inreplace "bin/ai-env-optimizer", "#!/usr/bin/env ruby", "#!#{formula_opt_bin("ruby")}/ruby"
    bin.install "bin/ai-env-optimizer"
    bin.install_symlink "ai-env-optimizer" => "ai-optimizer"
    lib.install "lib/ai_optimizer.rb", "lib/ai_optimizer"
    prefix.install "VERSION"
  end

  service do
    name macos: "homebrew.mxcl.ai-optimizer"
    run [opt_bin/"ai-env-optimizer", "run-maintenance"]
    run_type :cron
    cron "30 19 * * *"
    run_at_load false
    process_type :background
  end
end
```

Create `formula_renames.json`:

```json
{
  "ai-optimizer": "ai-env-optimizer"
}
```

Replace tap CI commands with the new formula name and assert the generated plist
label is exactly `homebrew.mxcl.ai-optimizer`.

- [ ] **Step 6: Verify Homebrew migration on Intel and Apple Silicon**

Open a tap PR, require `brew audit --strict --online`, install, formula test, and
service-info checks on both runners, merge, and verify exact-main CI.

- [ ] **Step 7: Upgrade this Mac without duplicating jobs**

Record the existing Homebrew formula, version, service label, schedule, and
latest owner-only maintenance receipt. Run `brew update` and upgrade the renamed
formula. Verify:

```bash
rtk ai-env-optimizer version
rtk ai-optimizer version
rtk brew list --versions ai-env-optimizer
rtk brew services info nyldn/tap/ai-env-optimizer --json
```

Expected: both commands report `ai-env-optimizer 0.2.0`; one formula is
installed; exactly one loaded service retains `homebrew.mxcl.ai-optimizer` and
the 19:30 schedule; no direct-install scheduler is enabled.

- [ ] **Step 8: Run final host health and storage inventory**

Run canonical doctor, scan, agent-context, storage JSON, native Claude doctor,
Codex doctor, MCP inventory, skills inventory, and launchd/cron audit. Do not run
storage cleanup until the user reviews its dry-run token and aggregate candidate
summary. Close the named browser session and report rollback instructions.

## Plan completion gate

The work is complete only when public exact-main CI, v0.2.0 release assets and
attestation, Homebrew dual-architecture CI, the installed local version, both
CLI names, one stable service label, the 19:30 schedule, read-only storage
inventory, and a final Fable 5 PASS all refer to the same released source.
