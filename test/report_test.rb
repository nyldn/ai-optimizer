# frozen_string_literal: true

require_relative "test_helper"

class ReportTest < Minitest::Test
  def findings
    [
      AIOptimizer::Finding.new(
        id: "tools.optional", category: "tools", status: "warn",
        message: "Optional tool missing", required: false
      ),
      AIOptimizer::Finding.new(
        id: "system.macos", category: "system", status: "pass",
        message: "macOS supported", required: true
      )
    ]
  end

  def test_json_and_text_share_order_and_summary
    report = AIOptimizer::Report.new(
      findings,
      generated_at: Time.utc(2026, 8, 22, 21, 0, 0),
      version: "0.1.0"
    )
    payload = JSON.parse(report.to_json)

    assert_equal "ai-env-optimizer", payload.fetch("product")
    assert_includes payload.fetch("compatibility").fetch("legacy_names"), "ai-optimizer"
    assert_equal %w[system.macos tools.optional], payload.fetch("findings").map { |item| item.fetch("id") }
    assert_equal({ "pass" => 1, "warn" => 1, "fail" => 0, "info" => 0, "skip" => 0, "unknown" => 0 }, payload.fetch("summary"))
    assert_includes report.to_text(color: false), "system.macos"
    assert_includes report.to_text(color: false), "1 passed, 1 warning"
  end

  def test_required_unknown_and_failure_exit_one
    unknown = AIOptimizer::Finding.new(
      id: "system.unknown", category: "system", status: "unknown",
      message: "Could not inspect system", required: true
    )
    assert_equal 1, AIOptimizer::Report.new([unknown]).exit_code
  end

  def test_optional_warning_only_fails_in_strict_mode
    report = AIOptimizer::Report.new(findings)
    assert_equal 0, report.exit_code
    assert_equal 1, report.exit_code(strict: true)
  end

  def test_rejects_duplicate_ids
    assert_raises(ArgumentError) { AIOptimizer::Report.new([findings.first, findings.first]) }
  end

  def test_redaction_keeps_truncated_unicode_valid
    text = "€" * 3_000
    scrubbed = AIOptimizer::Redactor.scrub(text)
    assert scrubbed.valid_encoding?
    JSON.generate("detail" => scrubbed)
  end
end
