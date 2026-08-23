# frozen_string_literal: true

require_relative "test_helper"

class StorageScannerTest < Minitest::Test
  NOW = Time.utc(2026, 8, 23, 12, 0, 0)

  def source(components: ["cache"], classification: "regenerable", eligible: true)
    AIOptimizer::StorageSource.new(
      id: "test.storage", provider: "test", base: :home,
      components: components, classification: classification,
      cleanup_eligible: eligible
    )
  end

  def scan(home, sources = [source])
    AIOptimizer::StorageScanner.new(
      sources: sources,
      home: home,
      data_dir: File.join(home, "data"),
      clock: -> { NOW }
    ).scan
  end

  def test_measures_allocated_bytes_age_buckets_and_hard_links_once
    in_tmpdir do |home|
      root = File.join(home, "cache")
      FileUtils.mkdir_p(root)
      fresh = File.join(root, "fresh-private-name")
      old = File.join(root, "old-private-name")
      linked = File.join(root, "hard-link-private-name")
      File.write(fresh, "f" * 8_192)
      File.write(old, "o" * 8_192)
      File.link(old, linked)
      File.utime(NOW - (3 * 86_400), NOW - (3 * 86_400), fresh)
      File.utime(NOW - (45 * 86_400), NOW - (45 * 86_400), old)

      measurement = scan(home).first

      assert_equal "complete", measurement.fetch("status")
      assert_operator measurement.fetch("allocated_bytes"), :>, 0
      assert_equal 2, measurement.fetch("file_count")
      assert_equal 1, measurement.fetch("directory_count")
      assert_equal measurement.fetch("allocated_bytes"), measurement.fetch("age_buckets").values.sum
      assert_operator measurement.fetch("age_buckets").fetch("0_7_days"), :>, 0
      assert_operator measurement.fetch("age_buckets").fetch("31_90_days"), :>, 0
      serialized = JSON.generate(measurement)
      refute_includes serialized, home
      refute_includes serialized, "private-name"
    end
  end

  def test_age_bucket_boundaries_are_complete
    in_tmpdir do |home|
      root = File.join(home, "cache")
      FileUtils.mkdir_p(root)
      { 7 => "0_7_days", 8 => "8_30_days", 30 => "8_30_days",
        31 => "31_90_days", 90 => "31_90_days", 91 => "over_90_days" }.each do |days, _bucket|
        path = File.join(root, "age-#{days}")
        File.write(path, "x" * 4_096)
        timestamp = NOW - (days * 86_400)
        File.utime(timestamp, timestamp, path)
      end

      buckets = scan(home).first.fetch("age_buckets")

      %w[0_7_days 8_30_days 31_90_days over_90_days].each do |name|
        assert_operator buckets.fetch(name), :>, 0
      end
    end
  end

  def test_missing_root_is_absent_and_symlinked_root_is_unknown
    in_tmpdir do |home|
      absent = scan(home).first
      assert_equal "absent", absent.fetch("status")
      assert_equal 0, absent.fetch("allocated_bytes")

      outside = File.join(home, "outside")
      FileUtils.mkdir_p(outside)
      File.write(File.join(outside, "secret"), "do not inspect")
      File.symlink(outside, File.join(home, "cache"))

      linked = scan(home).first
      assert_equal "unknown", linked.fetch("status")
      assert_equal 0, linked.fetch("allocated_bytes")
      refute_includes JSON.generate(linked), "outside"
    end
  end

  def test_symlinked_source_ancestor_is_unknown_and_not_followed
    in_tmpdir do |home|
      outside = File.join(home, "outside")
      FileUtils.mkdir_p(File.join(outside, "cache"))
      File.write(File.join(outside, "cache", "secret"), "do not inspect")
      File.symlink(outside, File.join(home, ".codex"))
      codex_source = source(components: [".codex", "cache"])

      measurement = scan(home, [codex_source]).first

      assert_equal "unknown", measurement.fetch("status")
      assert_equal 0, measurement.fetch("allocated_bytes")
      refute_includes JSON.generate(measurement), "outside"
    end
  end

  def test_large_directory_scan_does_not_modify_entries
    in_tmpdir do |home|
      root = File.join(home, "cache")
      FileUtils.mkdir_p(root)
      10_000.times { |index| File.write(File.join(root, "entry-#{index}"), "") }
      before = File.stat(root).mtime

      measurement = scan(home).first

      assert_equal "complete", measurement.fetch("status")
      assert_equal 10_000, measurement.fetch("file_count")
      assert_equal before, File.stat(root).mtime
    end
  end
end
