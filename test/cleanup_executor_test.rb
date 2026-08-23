# frozen_string_literal: true

require_relative "test_helper"

class CleanupExecutorTest < Minitest::Test
  NOW = Time.utc(2026, 8, 23, 23, 15, 0)

  def source(classification: "regenerable", eligible: true, process_names: ["TestAI"])
    AIOptimizer::StorageSource.new(
      id: eligible ? "test.cache" : "test.sessions",
      provider: "test",
      base: :home,
      components: [eligible ? "cache" : "sessions"],
      classification: classification,
      cleanup_eligible: eligible,
      process_names: process_names
    )
  end

  def write_old_file(path, content: "x" * 1024 * 1024)
    FileUtils.mkdir_p(File.dirname(path))
    File.binwrite(path, content)
    timestamp = NOW - (45 * 86_400)
    File.utime(timestamp, timestamp, path)
  end

  def build_fixture(home, sources: [source], process_guard: ->(_names) { false },
                    device_reader: ->(path) { File.stat(path).dev }, mover: nil)
    data_dir = File.join(home, "product-data")
    trash_root = File.join(home, ".Trash")
    FileUtils.mkdir_p(trash_root)
    planner = AIOptimizer::CleanupPlanner.new(
      sources: sources,
      home: home,
      data_dir: data_dir,
      clock: -> { NOW }
    )
    executor = AIOptimizer::CleanupExecutor.new(
      planner: planner,
      config: AIOptimizer::Config.new(data_dir: data_dir, default_workspace_root: home),
      trash_root: trash_root,
      clock: -> { NOW },
      process_guard: process_guard,
      device_reader: device_reader,
      mover: mover
    )
    [planner, executor, data_dir, trash_root]
  end

  def apply(executor, token)
    executor.apply(token: token, older_than_days: 30, min_size_mb: 1)
  end

  def test_moves_verified_candidates_to_private_trash_and_writes_private_receipt
    in_tmpdir do |home|
      original = File.join(home, "cache", "private-filename")
      write_old_file(original)
      planner, executor, data_dir = build_fixture(home)
      plan = planner.preview(older_than_days: 30, min_size_mb: 1)

      result = apply(executor, plan.token)

      assert_equal "moved_to_trash", result.fetch("status")
      assert_equal 1, result.fetch("moved_files")
      assert_equal 0o700, File.stat(result.fetch("trash_path_for_test")).mode & 0o777
      refute File.exist?(original)
      moved = File.join(result.fetch("trash_path_for_test"), "test.cache", "private-filename")
      assert File.file?(moved)
      receipt_path = File.join(data_dir, "reports", "latest-cleanup.json")
      assert_equal 0o600, File.stat(receipt_path).mode & 0o777
      receipt = JSON.parse(File.read(receipt_path))
      refute receipt.key?("trash_path_for_test")
      refute_includes JSON.generate(receipt), "private-filename"
      refute_includes JSON.generate(receipt), home
    end
  end

  def test_refuses_token_mismatch_and_metadata_drift
    in_tmpdir do |home|
      path = File.join(home, "cache", "candidate")
      write_old_file(path)
      planner, executor = build_fixture(home)
      plan = planner.preview(older_than_days: 30, min_size_mb: 1)

      assert_raises(AIOptimizer::UsageError) { apply(executor, "0" * 64) }
      File.open(path, "ab") { |file| file.write("changed") }
      File.utime(NOW - (45 * 86_400), NOW - (45 * 86_400), path)
      assert_raises(AIOptimizer::UsageError) { apply(executor, plan.token) }
      assert File.exist?(path)
    end
  end

  def test_refuses_running_provider_and_symlinked_candidate
    in_tmpdir do |home|
      path = File.join(home, "cache", "candidate")
      write_old_file(path)
      planner, executor = build_fixture(home, process_guard: ->(names) { names.include?("TestAI") })
      plan = planner.preview(older_than_days: 30, min_size_mb: 1)

      assert_raises(AIOptimizer::InternalError) { apply(executor, plan.token) }
      assert File.exist?(path)

      planner, executor = build_fixture(home)
      plan = planner.preview(older_than_days: 30, min_size_mb: 1)
      FileUtils.rm_f(path)
      outside = File.join(home, "outside")
      File.write(outside, "keep")
      File.symlink(outside, path)
      assert_raises(AIOptimizer::OwnershipError) { apply(executor, plan.token) }
      assert_equal "keep", File.read(outside)
    end
  end

  def test_refuses_symlinked_trash_existing_destination_and_cross_device_move
    in_tmpdir do |home|
      path = File.join(home, "cache", "candidate")
      write_old_file(path)
      planner, executor, _data_dir, trash_root = build_fixture(home)
      plan = planner.preview(older_than_days: 30, min_size_mb: 1)
      FileUtils.rm_rf(trash_root)
      real_trash = File.join(home, "real-trash")
      FileUtils.mkdir_p(real_trash)
      File.symlink(real_trash, trash_root)
      assert_raises(AIOptimizer::OwnershipError) { apply(executor, plan.token) }

      FileUtils.rm_f(trash_root)
      FileUtils.mkdir_p(trash_root)
      destination = File.join(trash_root, "ai-env-optimizer-20260823T231500Z-#{plan.token[0, 12]}")
      FileUtils.mkdir_p(destination)
      assert_raises(AIOptimizer::OwnershipError) { apply(executor, plan.token) }

      FileUtils.rm_rf(destination)
      planner, executor = build_fixture(
        home,
        device_reader: ->(candidate) { candidate == trash_root ? 2 : 1 }
      )
      assert_raises(AIOptimizer::OwnershipError) { apply(executor, plan.token) }
      assert File.exist?(path)
    end
  end

  def test_partial_failure_stops_and_records_completed_moves
    in_tmpdir do |home|
      first = File.join(home, "cache", "a")
      second = File.join(home, "cache", "b")
      write_old_file(first)
      write_old_file(second)
      calls = 0
      mover = lambda do |from, to|
        calls += 1
        raise Errno::EIO, "simulated move failure" if calls == 2

        File.rename(from, to)
      end
      planner, executor, data_dir = build_fixture(home, mover: mover)
      plan = planner.preview(older_than_days: 30, min_size_mb: 1)

      assert_raises(AIOptimizer::InternalError) { apply(executor, plan.token) }
      receipt = JSON.parse(File.read(File.join(data_dir, "reports", "latest-cleanup.json")))
      assert_equal "partial", receipt.fetch("status")
      assert_equal 1, receipt.fetch("moved_files")
      assert_equal 1, [first, second].count { |path| File.exist?(path) }
    end
  end

  def test_protected_sources_are_never_moved
    in_tmpdir do |home|
      protected = source(classification: "historical", eligible: false, process_names: [])
      path = File.join(home, "sessions", "history")
      write_old_file(path)
      planner, executor = build_fixture(home, sources: [protected])
      plan = planner.preview(older_than_days: 30, min_size_mb: 1)

      assert_empty plan.candidates
      assert_raises(AIOptimizer::UsageError) { apply(executor, plan.token) }
      assert File.exist?(path)
    end
  end
end
