# frozen_string_literal: true

require_relative "test_helper"

class AgentContextTest < Minitest::Test
  NOW = Time.utc(2026, 8, 23, 6, 0, 0)

  def test_builds_a_read_only_agent_contract_with_prioritized_unique_actions
    warning = AIOptimizer::Finding.new(
      id: "tools.codex.present",
      category: "tools",
      status: "warn",
      message: "Codex needs attention",
      remediation: "Inspect the preferred Codex installation.",
      affects: ["codex"]
    )
    required_failure = AIOptimizer::Finding.new(
      id: "product.config",
      category: "product",
      status: "fail",
      message: "Configuration is invalid",
      remediation: "Repair AI Optimizer configuration.",
      required: true,
      affects: ["ai-optimizer"]
    )
    passing = AIOptimizer::Finding.new(
      id: "system.macos",
      category: "system",
      status: "pass",
      message: "macOS is supported"
    )
    doctor = AIOptimizer::Report.new([warning, passing], generated_at: NOW)
    scan = AIOptimizer::Report.new([warning, required_failure], generated_at: NOW)

    payload = AIOptimizer::AgentContext.new(
      doctor_report: doctor,
      scan_report: scan,
      generated_at: NOW
    ).to_h

    assert_equal "read_only_advisor", payload.fetch(:mode)
    assert_equal "action_required", payload.fetch(:overall_status)
    assert_equal true, payload.fetch(:agent_contract).fetch(:diagnostics_are_read_only)
    assert_equal false, payload.fetch(:agent_contract).fetch(:repairs_are_automatic)
    assert_equal %w[P0 P2], payload.fetch(:prioritized_actions).map { |action| action.fetch(:priority) }
    assert_equal 1, payload.fetch(:prioritized_actions).count { |action| action.fetch(:finding_id) == warning.id }
    refute payload.fetch(:prioritized_actions).any? { |action| action.fetch(:finding_id) == passing.id }
    assert_equal doctor.to_h, payload.fetch(:reports).fetch(:doctor)
    assert_equal scan.to_h, payload.fetch(:reports).fetch(:scan)
  end

  def test_text_output_tells_an_agent_how_to_continue
    report = AIOptimizer::Report.new([], generated_at: NOW)
    context = AIOptimizer::AgentContext.new(
      doctor_report: report,
      scan_report: report,
      generated_at: NOW
    )

    text = context.to_text

    assert_includes text, "Mode: read-only advisor"
    assert_includes text, "Overall: healthy"
    assert_includes text, "Do not expose credentials"
    assert_includes text, "Re-run agent-context after any approved repair"
  end
end
