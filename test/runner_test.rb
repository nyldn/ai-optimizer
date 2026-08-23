# frozen_string_literal: true

require_relative "test_helper"

class RunnerTest < Minitest::Test
  def test_records_only_executable_basename
    result = AIOptimizer::CommandRunner.new.run(["/usr/bin/printf", "%s", "secret-argument"])

    assert_equal "printf", result.command
    refute_includes result.to_h.values.join(" "), "%s"
    refute_includes result.to_h.values.join(" "), "secret-argument"
  end

  def test_redacts_home_paths_from_captured_output
    in_tmpdir do |home|
      result = AIOptimizer::CommandRunner.new(home: home).run(
        ["/usr/bin/printf", "%s", File.join(home, "private", "file")]
      )

      refute_includes result.stdout, home
      assert_equal "~/private/file", result.stdout
    end
  end

  def test_times_out_hung_process
    result = AIOptimizer::CommandRunner.new.run(["/bin/sleep", "2"], timeout: 0.05)

    assert result.timed_out
    refute_equal 0, result.status
  end
end
