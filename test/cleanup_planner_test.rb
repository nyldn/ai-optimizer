# frozen_string_literal: true

require_relative "test_helper"

class CleanupPlannerTest < Minitest::Test
  NOW = Time.utc(2026, 8, 23, 12, 0, 0)

  def source(id:, components:, classification:, eligible:)
    AIOptimizer::StorageSource.new(
      id: id, provider: "test", base: :home, components: components,
      classification: classification, cleanup_eligible: eligible
    )
  end

  def planner(home, sources)
    AIOptimizer::CleanupPlanner.new(
      sources: sources,
      home: home,
      data_dir: File.join(home, "product-data"),
      clock: -> { NOW }
    )
  end

  def write_old_file(path, bytes: 1024 * 1024)
    FileUtils.mkdir_p(File.dirname(path))
    File.open(path, "wb") { |file| file.write("x" * bytes) }
    timestamp = NOW - (45 * 86_400)
    File.utime(timestamp, timestamp, path)
  end

  def test_selects_only_allowlisted_sources_and_never_history
    in_tmpdir do |home|
      cache_source = source(
        id: "test.cache", components: ["cache"],
        classification: "regenerable", eligible: true
      )
      history_source = source(
        id: "test.sessions", components: ["sessions"],
        classification: "historical", eligible: false
      )
      write_old_file(File.join(home, "cache", "cache-private-name"))
      write_old_file(File.join(home, "sessions", "session-private-name"))

      plan = planner(home, [cache_source, history_source]).preview(
        older_than_days: 30,
        min_size_mb: 1
      )
      payload = plan.to_h

      assert_equal ["test.cache"], payload.fetch("sources").map { |item| item.fetch("id") }
      assert payload.fetch("sources").all? { |item| item.fetch("cleanup_eligible") }
      assert_equal 1, payload.fetch("summary").fetch("candidate_files")
      assert_match(/\A[0-9a-f]{64}\z/, payload.fetch("token"))
      serialized = JSON.generate(payload)
      refute_includes serialized, home
      refute_includes serialized, "private-name"
      assert plan.candidates.all? { |candidate| candidate.source.id == "test.cache" }
    end
  end

  def test_defaults_and_source_level_minimum_are_enforced
    in_tmpdir do |home|
      cache_source = source(
        id: "test.cache", components: ["cache"],
        classification: "regenerable", eligible: true
      )
      write_old_file(File.join(home, "cache", "small"), bytes: 4_096)

      plan = planner(home, [cache_source]).preview

      assert_equal 30, plan.older_than_days
      assert_equal 100, plan.min_size_mb
      assert_empty plan.candidates
      assert_empty plan.to_h.fetch("sources")
    end
  end

  def test_token_is_deterministic_and_changes_after_metadata_drift
    in_tmpdir do |home|
      cache_source = source(
        id: "test.cache", components: ["cache"],
        classification: "regenerable", eligible: true
      )
      path = File.join(home, "cache", "candidate")
      write_old_file(path)
      cleanup_planner = planner(home, [cache_source])

      first = cleanup_planner.preview(older_than_days: 30, min_size_mb: 1)
      second = cleanup_planner.preview(older_than_days: 30, min_size_mb: 1)
      assert_equal first.token, second.token

      File.open(path, "ab") { |file| file.write("changed") }
      File.utime(NOW - (45 * 86_400), NOW - (45 * 86_400), path)
      changed = cleanup_planner.preview(older_than_days: 30, min_size_mb: 1)
      refute_equal first.token, changed.token
    end
  end

  def test_refuses_symlinks_and_invalid_filters
    in_tmpdir do |home|
      cache_source = source(
        id: "test.cache", components: ["cache"],
        classification: "regenerable", eligible: true
      )
      outside = File.join(home, "outside")
      FileUtils.mkdir_p(File.join(home, "cache"))
      File.write(outside, "outside")
      File.symlink(outside, File.join(home, "cache", "linked"))
      cleanup_planner = planner(home, [cache_source])

      assert_raises(AIOptimizer::OwnershipError) do
        cleanup_planner.preview(older_than_days: 30, min_size_mb: 1)
      end
      assert_raises(AIOptimizer::UsageError) { cleanup_planner.preview(older_than_days: 0) }
      assert_raises(AIOptimizer::UsageError) { cleanup_planner.preview(older_than_days: 3651) }
      assert_raises(AIOptimizer::UsageError) { cleanup_planner.preview(min_size_mb: 0) }
    end
  end

  def test_refuses_a_symlinked_source_ancestor
    in_tmpdir do |home|
      outside = File.join(home, "outside")
      FileUtils.mkdir_p(File.join(outside, "cache"))
      write_old_file(File.join(outside, "cache", "candidate"))
      File.symlink(outside, File.join(home, ".codex"))
      cache_source = source(
        id: "test.cache", components: [".codex", "cache"],
        classification: "regenerable", eligible: true
      )

      assert_raises(AIOptimizer::OwnershipError) do
        planner(home, [cache_source]).preview(older_than_days: 30, min_size_mb: 1)
      end
    end
  end
end
