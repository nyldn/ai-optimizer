# frozen_string_literal: true

require_relative "test_helper"

class MaintenanceTest < Minitest::Test
  def storage_report(allocated:, protected:, reclaimable:, unknown:)
    Struct.new(:summary).new(
      {
        "allocated_bytes" => allocated,
        "protected_bytes" => protected,
        "reclaimable_bytes" => reclaimable,
        "unknown_sources" => unknown
      }
    )
  end

  def test_receipt_carries_the_canonical_and_legacy_product_names
    in_tmpdir do |dir|
      receipt = AIOptimizer::Maintenance.new(
        data_dir: dir,
        clock: -> { Time.local(2026, 8, 23, 21, 0, 0) },
        doctor: -> { AIOptimizer::Report.new([], generated_at: Time.utc(2026, 8, 24, 1, 0, 0)) }
      ).run

      assert_equal "ai-env-optimizer", receipt.fetch("product")
      assert_includes receipt.fetch("compatibility").fetch("legacy_names"), "ai-optimizer"
      assert_equal receipt, JSON.parse(File.read(File.join(dir, "reports", "latest-run.json")))
    end
  end

  def test_inside_window_records_report_only_storage_warning
    in_tmpdir do |dir|
      cleanup_calls = 0
      receipt = AIOptimizer::Maintenance.new(
        data_dir: dir,
        clock: -> { Time.local(2026, 8, 23, 21, 0, 0) },
        doctor: -> { AIOptimizer::Report.new([], generated_at: Time.utc(2026, 8, 24, 1, 0, 0)) },
        storage: lambda {
          storage_report(
            allocated: 12_000_000_000,
            protected: 9_000_000_000,
            reclaimable: 3_000_000_000,
            unknown: 2
          )
        },
        warning_bytes: 10 * 1024 * 1024 * 1024
      ).run

      assert_equal 12_000_000_000, receipt.fetch("storage").fetch("allocated_bytes")
      assert_equal "warning", receipt.fetch("storage").fetch("status")
      assert_equal 9_000_000_000, receipt.fetch("storage").fetch("protected_bytes")
      assert_equal 3_000_000_000, receipt.fetch("storage").fetch("reclaimable_bytes")
      assert_equal 2, receipt.fetch("storage").fetch("unknown_sources")
      assert_equal 0, cleanup_calls
    end
  end

  def test_outside_window_does_not_scan_storage
    in_tmpdir do |dir|
      storage_calls = 0
      receipt = AIOptimizer::Maintenance.new(
        data_dir: dir,
        clock: -> { Time.local(2026, 8, 23, 12, 0, 0) },
        doctor: -> { raise "doctor must not run" },
        storage: lambda {
          storage_calls += 1
          raise "storage must not run"
        }
      ).run

      assert_equal "skipped_outside_window", receipt.fetch("status")
      assert_equal 0, storage_calls
      refute receipt.key?("storage")
    end
  end
end
