# frozen_string_literal: true

require_relative "test_helper"

class ChecksTest < Minitest::Test
  def test_doctor_is_useful_without_optional_tools
    in_tmpdir do |dir|
      context = AIOptimizer::CheckContext.new(
        home: dir,
        data_dir: File.join(dir, "data"),
        workspace_root: File.join(dir, "workspaces"),
        path: "",
        runner: TestSupport::FakeCommandRunner.new,
        platform: "darwin",
        architecture: "arm64",
        macos_version: "15.6"
      )
      report = AIOptimizer::Doctor.new(context).run

      assert_equal 0, report.exit_code
      assert report.findings.any? { |finding| finding.id == "tools.claude.present" && finding.status == "warn" }
      assert report.findings.any? { |finding| finding.id == "tools.codex.present" && finding.status == "warn" }
      assert report.findings.any? { |finding| finding.id == "system.macos" && finding.status == "pass" }
    end
  end

  def test_mcp_details_never_expose_endpoints_or_tokens
    in_tmpdir do |dir|
      File.write(
        File.join(dir, ".claude.json"),
        JSON.generate("mcpServers" => { "private" => { "url" => "https://secret.example/mcp?token=abc123" } })
      )
      context = AIOptimizer::CheckContext.new(
        home: dir, data_dir: File.join(dir, "data"), workspace_root: dir,
        path: "", runner: TestSupport::FakeCommandRunner.new,
        platform: "darwin", architecture: "x86_64", macos_version: "14.7"
      )
      output = AIOptimizer::Doctor.new(context).run.to_json

      refute_includes output, "secret.example"
      refute_includes output, "abc123"
      assert_includes output, "1 configured server"
    end
  end

  def test_workspace_scan_reports_counts_not_names
    in_tmpdir do |dir|
      root = File.join(dir, "workspaces")
      private_name = "confidential-customer"
      repo = File.join(root, private_name)
      FileUtils.mkdir_p(File.join(repo, ".git"))
      File.write(File.join(repo, "AGENTS.md"), "instructions")
      context = AIOptimizer::CheckContext.new(
        home: dir, data_dir: File.join(dir, "data"), workspace_root: root,
        path: "", runner: TestSupport::FakeCommandRunner.new,
        platform: "darwin", architecture: "arm64", macos_version: "15.6"
      )
      output = AIOptimizer::Scanner.new(context).run.to_json

      refute_includes output, private_name
      assert_includes output, "1 Git workspace"
    end
  end

  def test_agentation_atk_launch_agent_counts_as_installed
    in_tmpdir do |dir|
      launch_agents = File.join(dir, "Library", "LaunchAgents")
      FileUtils.mkdir_p(launch_agents)
      File.write(File.join(launch_agents, "com.agentation.mcp-server.plist"), "fixture")
      context = AIOptimizer::CheckContext.new(
        home: dir, data_dir: File.join(dir, "data"), workspace_root: dir,
        path: "", runner: TestSupport::FakeCommandRunner.new,
        platform: "darwin", architecture: "arm64", macos_version: "15.6"
      )

      finding = AIOptimizer::Doctor.new(context).run.findings.find { |item| item.id == "tools.atk.present" }
      assert_equal "pass", finding.status
      assert_includes finding.message, "Agentation"
    end
  end

  def test_claude_mem_plugin_counts_as_installed
    in_tmpdir do |dir|
      plugin = File.join(dir, ".codex", "plugins", "cache", "claude-mem-local", "claude-mem", "13.15.3")
      FileUtils.mkdir_p(plugin)
      context = AIOptimizer::CheckContext.new(
        home: dir, data_dir: File.join(dir, "data"), workspace_root: dir,
        path: "", runner: TestSupport::FakeCommandRunner.new,
        platform: "darwin", architecture: "arm64", macos_version: "15.6"
      )

      finding = AIOptimizer::Doctor.new(context).run.findings.find { |item| item.id == "tools.claude_mem.present" }
      assert_equal "pass", finding.status
      assert_includes finding.detail, "plugin"
    end
  end

  def test_path_aliases_to_same_executable_are_not_duplicates
    in_tmpdir do |dir|
      first = File.join(dir, "first")
      second = File.join(dir, "second")
      FileUtils.mkdir_p([first, second])
      executable = File.join(first, "codex")
      File.write(executable, "fixture")
      File.chmod(0o755, executable)
      File.symlink(executable, File.join(second, "codex"))
      context = AIOptimizer::CheckContext.new(
        home: dir, data_dir: File.join(dir, "data"), workspace_root: dir,
        path: [first, second].join(File::PATH_SEPARATOR),
        runner: TestSupport::FakeCommandRunner.new,
        platform: "darwin", architecture: "arm64", macos_version: "15.6"
      )

      finding = AIOptimizer::Doctor.new(context).run.findings.find { |item| item.id == "tools.codex.present" }
      assert_equal "pass", finding.status
      refute_includes finding.detail, "PATH matches"
    end
  end

  def test_distinct_path_matches_use_non_destructive_remediation
    in_tmpdir do |dir|
      first = File.join(dir, "first")
      second = File.join(dir, "second")
      FileUtils.mkdir_p([first, second])
      [first, second].each do |root|
        executable = File.join(root, "codex")
        File.write(executable, "fixture")
        File.chmod(0o755, executable)
      end
      context = AIOptimizer::CheckContext.new(
        home: dir, data_dir: File.join(dir, "data"), workspace_root: dir,
        path: [first, second].join(File::PATH_SEPARATOR),
        runner: TestSupport::FakeCommandRunner.new,
        platform: "darwin", architecture: "arm64", macos_version: "15.6"
      )

      finding = AIOptimizer::Doctor.new(context).run.findings.find { |item| item.id == "tools.codex.present" }
      assert_equal "warn", finding.status
      assert_includes finding.remediation, "preferred codex"
      refute_includes finding.remediation, "Remove stale PATH entries"
    end
  end

  def test_skill_names_shared_across_tool_roots_are_informational
    in_tmpdir do |dir|
      [".claude", ".codex"].each do |tool_root|
        skill = File.join(dir, tool_root, "skills", "shared-skill")
        FileUtils.mkdir_p(skill)
        File.write(File.join(skill, "SKILL.md"), "---\nname: shared-skill\ndescription: fixture\n---\n")
      end
      context = AIOptimizer::CheckContext.new(
        home: dir, data_dir: File.join(dir, "data"), workspace_root: dir,
        path: "", runner: TestSupport::FakeCommandRunner.new,
        platform: "darwin", architecture: "arm64", macos_version: "15.6"
      )

      finding = AIOptimizer::Doctor.new(context).run.findings.find { |item| item.id == "skills.inventory" }
      assert_equal "info", finding.status
      assert_includes finding.detail, "shared across tool roots"
      assert_nil finding.remediation
    end
  end

  def test_invalid_skill_frontmatter_still_warns
    in_tmpdir do |dir|
      skill = File.join(dir, ".codex", "skills", "invalid")
      FileUtils.mkdir_p(skill)
      File.write(File.join(skill, "SKILL.md"), "missing frontmatter")
      context = AIOptimizer::CheckContext.new(
        home: dir, data_dir: File.join(dir, "data"), workspace_root: dir,
        path: "", runner: TestSupport::FakeCommandRunner.new,
        platform: "darwin", architecture: "arm64", macos_version: "15.6"
      )

      finding = AIOptimizer::Doctor.new(context).run.findings.find { |item| item.id == "skills.inventory" }
      assert_equal "warn", finding.status
      assert_includes finding.remediation, "frontmatter"
    end
  end
end
