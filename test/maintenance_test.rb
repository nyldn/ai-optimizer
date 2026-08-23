# frozen_string_literal: true

require_relative "test_helper"

class MaintenanceTest < Minitest::Test
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
end
