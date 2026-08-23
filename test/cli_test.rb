# frozen_string_literal: true

require_relative "test_helper"

class CLITest < Minitest::Test
  BIN = File.expand_path("../bin/ai-env-optimizer", __dir__)
  LEGACY_BIN = File.expand_path("../bin/ai-optimizer", __dir__)

  def run_cli(*args, env: {})
    Open3.capture3(env, "/usr/bin/ruby", BIN, *args)
  end

  def test_version_and_help
    stdout, stderr, status = run_cli("version")
    assert status.success?, stderr
    assert_equal "ai-env-optimizer #{AIOptimizer::VERSION}\n", stdout

    stdout, stderr, status = run_cli("help")
    assert status.success?, stderr
    assert_includes stdout, "doctor"
    assert_includes stdout, "schedule"
    assert_includes stdout, "doctor, scan, and agent-context are read-only"
  end

  def test_legacy_command_remains_a_working_alias
    stdout, stderr, status = Open3.capture3("/usr/bin/ruby", LEGACY_BIN, "version")

    assert status.success?, stderr
    assert_equal "ai-env-optimizer #{AIOptimizer::VERSION}\n", stdout
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

  def test_agent_context_json_is_one_actionable_document
    in_tmpdir do |dir|
      stdout, stderr, status = run_cli(
        "agent-context", "--json", "--workspace-root", dir,
        env: { "AI_OPTIMIZER_DATA_DIR" => File.join(dir, "data") }
      )
      assert_includes [0, 1], status.exitstatus, stderr
      payload = JSON.parse(stdout)
      assert_equal "ai-env-optimizer", payload.fetch("product")
      assert_includes payload.fetch("compatibility").fetch("legacy_names"), "ai-optimizer"
      assert_equal "read_only_advisor", payload.fetch("mode")
      assert payload.fetch("agent_contract").fetch("workflow").any?
      assert payload.fetch("reports").fetch("doctor").fetch("findings").is_a?(Array)
      assert payload.fetch("reports").fetch("scan").fetch("findings").is_a?(Array)
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

  def test_canonical_environment_variable_takes_precedence_over_legacy_name
    in_tmpdir do |dir|
      canonical = File.join(dir, "canonical-data")
      legacy = File.join(dir, "legacy-data")
      _stdout, stderr, status = run_cli(
        "setup", "--workspace-root", dir,
        env: {
          "AI_ENV_OPTIMIZER_DATA_DIR" => canonical,
          "AI_OPTIMIZER_DATA_DIR" => legacy
        }
      )

      assert status.success?, stderr
      assert File.file?(File.join(canonical, "config.json"))
      refute File.exist?(legacy)
    end
  end
end
