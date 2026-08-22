# frozen_string_literal: true

require_relative "test_helper"

class FindingTest < Minitest::Test
  def test_serializes_complete_stable_contract
    finding = AIOptimizer::Finding.new(
      id: "tools.codex.present",
      category: "tools",
      status: "pass",
      message: "Codex is available",
      detail: "codex 0.149.0",
      remediation: nil,
      required: false,
      affects: ["codex"],
      links: ["https://developers.openai.com/codex/cli"]
    )

    assert_equal(
      %w[id category status message detail remediation required affects links],
      finding.to_h.keys.map(&:to_s)
    )
    assert_equal "tools.codex.present", finding.to_h[:id]
  end

  def test_rejects_invalid_status
    error = assert_raises(ArgumentError) do
      AIOptimizer::Finding.new(
        id: "bad", category: "test", status: "maybe", message: "bad"
      )
    end

    assert_match(/status/, error.message)
  end

  def test_rejects_empty_id
    assert_raises(ArgumentError) do
      AIOptimizer::Finding.new(id: "", category: "test", status: "pass", message: "bad")
    end
  end
end
