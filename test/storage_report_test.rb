# frozen_string_literal: true

require_relative "test_helper"

class StorageReportTest < Minitest::Test
  def measurements
    [
      {
        "id" => "codex.sessions", "provider" => "codex",
        "classification" => "historical", "cleanup_eligible" => false,
        "status" => "complete", "allocated_bytes" => 2_048,
        "file_count" => 2, "directory_count" => 1,
        "age_buckets" => { "0_7_days" => 1_024, "8_30_days" => 1_024,
                           "31_90_days" => 0, "over_90_days" => 0 },
        "path" => "/private/session/path", "filename" => "secret.jsonl"
      },
      {
        "id" => "claude.app_cache", "provider" => "claude",
        "classification" => "regenerable", "cleanup_eligible" => true,
        "status" => "complete", "allocated_bytes" => 4_096,
        "file_count" => 4, "directory_count" => 1,
        "age_buckets" => { "0_7_days" => 0, "8_30_days" => 0,
                           "31_90_days" => 4_096, "over_90_days" => 0 }
      }
    ]
  end

  def test_json_is_deterministic_canonical_and_path_free
    report = AIOptimizer::StorageReport.new(
      measurements.reverse,
      generated_at: Time.utc(2026, 8, 23, 12, 0, 0),
      version: "0.2.0",
      warning_bytes: 10_000
    )
    payload = JSON.parse(report.to_json)

    assert_equal "ai-env-optimizer", payload.fetch("product")
    assert_includes payload.fetch("compatibility").fetch("legacy_names"), "ai-optimizer"
    assert_equal %w[claude.app_cache codex.sessions], payload.fetch("sources").map { |item| item.fetch("id") }
    assert_equal 6_144, payload.fetch("summary").fetch("allocated_bytes")
    assert_equal 4_096, payload.fetch("summary").fetch("reclaimable_bytes")
    assert_equal 2_048, payload.fetch("summary").fetch("protected_bytes")
    refute_includes report.to_json, "/private/session/path"
    refute_includes report.to_json, "secret.jsonl"
  end

  def test_human_output_explains_protection_without_paths
    report = AIOptimizer::StorageReport.new(measurements, warning_bytes: 10_000)
    text = report.to_text

    assert_includes text, "AI Environment Optimizer storage"
    assert_includes text, "[PROTECTED] codex.sessions"
    assert_includes text, "[RECLAIMABLE] claude.app_cache"
    refute_includes text, "/private/session/path"
  end

  def test_unknown_sources_fail_and_threshold_only_fails_strict
    report = AIOptimizer::StorageReport.new(measurements, warning_bytes: 1)
    assert_equal 0, report.exit_code
    assert_equal 1, report.exit_code(strict: true)

    unknown = measurements.first.merge("status" => "unknown", "allocated_bytes" => 0)
    assert_equal 1, AIOptimizer::StorageReport.new([unknown], warning_bytes: 10_000).exit_code
  end
end
