# frozen_string_literal: true

require_relative "test_helper"

class RunnerTest < Minitest::Test
  def test_records_only_executable_basename
    result = AIOptimizer::CommandRunner.new.run(["/usr/bin/printf", "%s", "secret-argument"])

    assert_equal "printf", result.command
    refute_includes result.to_h.values.join(" "), "%s"
    refute_includes result.to_h.values.join(" "), "secret-argument"
  end

  def test_times_out_hung_process
    result = AIOptimizer::CommandRunner.new.run(["/bin/sleep", "2"], timeout: 0.05)

    assert result.timed_out
    refute_equal 0, result.status
  end
end
