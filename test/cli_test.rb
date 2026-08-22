# frozen_string_literal: true

require_relative "test_helper"

class CLITest < Minitest::Test
  BIN = File.expand_path("../bin/ai-optimizer", __dir__)

  def run_cli(*args, env: {})
    Open3.capture3(env, "/usr/bin/ruby", BIN, *args)
  end

  def test_version_and_help
    stdout, stderr, status = run_cli("version")
    assert status.success?, stderr
    assert_equal "ai-optimizer #{AIOptimizer::VERSION}\n", stdout

    stdout, stderr, status = run_cli("help")
    assert status.success?, stderr
    assert_includes stdout, "doctor"
    assert_includes stdout, "schedule"
  end

  def test_doctor_json_is_one_document
    in_tmpdir do |dir|
      stdout, stderr, status = run_cli("doctor", "--json", env: { "AI_OPTIMIZER_DATA_DIR" => File.join(dir, "data") })
      assert_includes [0, 1], status.exitstatus, stderr
      payload = JSON.parse(stdout)
      assert payload.key?("findings")
      assert_empty stderr
    end
  end

  def test_usage_error_exits_two
    _stdout, stderr, status = run_cli("doctor", "--not-a-real-flag")
    assert_equal 2, status.exitstatus
    assert_includes stderr, "Usage"
  end

  def test_setup_rejects_missing_workspace_root
    in_tmpdir do |dir|
      missing = File.join(dir, "missing")
      _stdout, stderr, status = run_cli(
        "setup", "--workspace-root", missing,
        env: { "AI_OPTIMIZER_DATA_DIR" => File.join(dir, "data") }
      )
      assert_equal 2, status.exitstatus
      assert_includes stderr, "workspace root"
      refute File.exist?(File.join(dir, "data", "config.json"))
    end
  end
end
