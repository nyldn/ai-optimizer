# frozen_string_literal: true

require_relative "test_helper"

class DesktopTest < Minitest::Test
  def context(home, results = {}, roots = nil, path = "")
    AIOptimizer::CheckContext.new(
      home: home, data_dir: File.join(home, "data"), workspace_root: home,
      path: path, runner: TestSupport::FakeCommandRunner.new(results),
      platform: "darwin", architecture: "arm64", macos_version: "15.6",
      application_roots: roots || [File.join(home, "Applications")]
    )
  end

  def app(home, name, identifier, results)
    root = File.join(home, "Applications", "#{name}.app")
    FileUtils.mkdir_p(File.join(root, "Contents", "MacOS"))
    File.write(File.join(root, "Contents", "MacOS", "app"), "do not run")
    File.chmod(0o755, File.join(root, "Contents", "MacOS", "app"))
    plist = File.join(root, "Contents", "Info.plist")
    File.write(plist, "fixture")
    {"CFBundleIdentifier" => identifier, "CFBundleShortVersionString" => "1.2.3", "CFBundleExecutable" => "app"}.each do |key, value|
      command = ["/usr/bin/plutil", "-extract", key, "raw", "-o", "-", File.realpath(plist)]
      results[command.join(" ")] = {stdout: value, status: 0}
    end
    root
  end

  def test_desktop_only_installations_do_not_request_cli_installation_as_a_repair
    in_tmpdir do |home|
      results = {}
      app(home, "Claude", "com.anthropic.claudefordesktop", results)
      app(home, "Codex", "com.openai.codex", results)
      ctx = context(home, results)
      report = AIOptimizer::Doctor.new(ctx).run
      %w[claude codex].each do |provider|
        assert_equal "pass", report.findings.find { |f| f.id == "desktop.#{provider}.present" }.status
        assert_equal "info", report.findings.find { |f| f.id == "tools.#{provider}.present" }.status
        limits = report.findings.find { |f| f.id == "desktop.#{provider}.capabilities" }
        assert_includes limits.detail, "CLI"
      end
      refute ctx.runner.calls.any? { |call| call[:argv].first.include?(".app/") }
      refute_includes report.to_json, home
    end
  end

  def test_current_chatgpt_bundle_identity_and_duplicate_apps_are_recognized
    in_tmpdir do |home|
      results = {}
      app(home, "Codex", "com.openai.codex", results)
      app(home, "ChatGPT", "com.openai.codex", results)
      report = AIOptimizer::Doctor.new(context(home, results)).run
      finding = report.findings.find { |f| f.id == "desktop.codex.present" }
      assert_equal "warn", finding.status
      assert_includes finding.detail, "2 distinct"
      assert_includes finding.remediation, "preferred"
    end
  end

  def test_bundled_runtime_on_path_is_not_executed_as_a_standalone_cli
    in_tmpdir do |home|
      results = {}
      root = app(home, "Codex", "com.openai.codex", results)
      resources = File.join(root, "Contents", "Resources")
      FileUtils.mkdir_p(resources)
      File.write(File.join(resources, "codex"), "do not run")
      File.chmod(0o755, File.join(resources, "codex"))
      ctx = context(home, results, nil, resources)
      report = AIOptimizer::Doctor.new(ctx).run
      assert_equal "info", report.findings.find { |f| f.id == "tools.codex.present" }.status
      refute ctx.runner.calls.any? { |call| call[:argv].first.include?(".app/") }
    end
  end

  def test_standalone_cli_and_desktop_are_reported_independently
    in_tmpdir do |home|
      results = {}
      app(home, "Claude", "com.anthropic.claudefordesktop", results)
      bin = File.join(home, "bin")
      FileUtils.mkdir_p(bin)
      File.write(File.join(bin, "claude"), "fixture")
      File.chmod(0o755, File.join(bin, "claude"))
      results["#{bin}/claude --version"] = {stdout: "1.2.3", status: 0}
      report = AIOptimizer::Doctor.new(context(home, results, nil, bin)).run
      assert_equal "pass", report.findings.find { |f| f.id == "tools.claude.present" }.status
      assert_equal "pass", report.findings.find { |f| f.id == "desktop.claude.present" }.status
    end
  end

  def test_missing_and_unreadable_apps_do_not_claim_runtime_readiness
    in_tmpdir do |home|
      report = AIOptimizer::Doctor.new(context(home)).run
      assert_equal "info", report.findings.find { |f| f.id == "desktop.claude.present" }.status
      results = {}
      app(home, "Claude", "com.anthropic.claudefordesktop", results)
      results[results.keys.first] = {stdout: "private-output", status: nil, timed_out: true}
      report = AIOptimizer::Doctor.new(context(home, results)).run
      assert_equal "unknown", report.findings.find { |f| f.id == "desktop.claude.present" }.status
      refute_includes report.to_json, "private-output"
    end
  end

  def test_legacy_chatgpt_identity_is_not_mistaken_for_codex
    in_tmpdir do |home|
      results = {}
      app(home, "ChatGPT", "com.openai.chat", results)
      report = AIOptimizer::Doctor.new(context(home, results)).run
      refute_equal "pass", report.findings.find { |f| f.id == "desktop.codex.present" }.status
      assert_equal "warn", report.findings.find { |f| f.id == "tools.codex.present" }.status
    end
  end

  def test_aliases_are_deduplicated_and_bad_metadata_is_not_reported
    in_tmpdir do |home|
      results = {}
      root = app(home, "Codex", "com.openai.codex", results)
      File.symlink(root, File.join(home, "Applications", "ChatGPT.app"))
      ctx = context(home, results)
      finding = AIOptimizer::Doctor.new(ctx).run.findings.find { |f| f.id == "desktop.codex.present" }
      assert_equal "pass", finding.status
      assert_includes finding.detail, "1.2.3"
      plist_key = results.keys.first
      results[plist_key] = {stdout: '{"CFBundleIdentifier":"secret-private-name"}', status: 0}
      report = AIOptimizer::Doctor.new(context(home, results)).run
      assert_equal "unknown", report.findings.find { |f| f.id == "desktop.codex.present" }.status
      refute_includes report.to_json, "secret-private-name"
    end
  end

  def test_desktop_mcp_inventory_is_separate_and_redacted
    in_tmpdir do |home|
      folder = File.join(home, "Library", "Application Support", "Claude")
      FileUtils.mkdir_p(folder)
      path = File.join(folder, "claude_desktop_config.json")
      File.write(path, JSON.generate("mcpServers" => {
        "private-server" => {"url" => "https://private.invalid/mcp", "env" => {"TOKEN" => "private-token"}}
      }))
      report = AIOptimizer::Doctor.new(context(home)).run
      finding = report.findings.find { |f| f.id == "mcp.claude_desktop.configured" }
      assert_includes finding.detail, "1 configured server"
      %w[private-server private.invalid private-token].each { |s| refute_includes report.to_json, s }
      assert_includes finding.detail, "not connection health"
      File.write(path, '{"mcpServers":[]}')
      report = AIOptimizer::Doctor.new(context(home)).run
      assert_equal "warn", report.findings.find { |f| f.id == "mcp.claude_desktop.parse" }.status
    end
  end

  def test_symlinked_desktop_config_directory_is_not_followed
    in_tmpdir do |home|
      parent = File.join(home, "Library", "Application Support")
      external = File.join(home, "private-config")
      FileUtils.mkdir_p([parent, external])
      File.write(File.join(external, "claude_desktop_config.json"), '{"mcpServers":{"private":{}}}')
      File.symlink(external, File.join(parent, "Claude"))
      report = AIOptimizer::Doctor.new(context(home)).run
      assert_equal "warn", report.findings.find { |f| f.id == "mcp.claude_desktop.parse" }.status
      refute_includes report.to_json, "1 configured server"
    end
  end

  def test_real_plutil_reads_only_allowlisted_fields_from_large_bundle_metadata
    in_tmpdir do |home|
      results = {}
      root = app(home, "Claude", "com.anthropic.claudefordesktop", results)
      plist = File.join(root, "Contents", "Info.plist")
      File.write(plist, <<~XML)
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict>
        <key>CFBundleIdentifier</key><string>com.anthropic.claudefordesktop</string>
        <key>CFBundleExecutable</key><string>app</string>
        <key>CFBundleShortVersionString</key><string>1.2.3</string>
        <key>UnrelatedMetadata</key><string>#{'private-metadata' * 1000}</string>
        </dict></plist>
      XML
      ctx = AIOptimizer::CheckContext.new(
        home: home, data_dir: File.join(home, "data"), workspace_root: home,
        path: "", runner: AIOptimizer::CommandRunner.new(home: home),
        platform: "darwin", architecture: "arm64", macos_version: "15.6",
        application_roots: [File.join(home, "Applications")]
      )
      report = AIOptimizer::Report.new(AIOptimizer::DesktopCheck.new(ctx).call)
      assert_equal "pass", report.findings.find { |f| f.id == "desktop.claude.present" }.status
      refute_includes report.to_json, "private-metadata"
      assert_includes report.to_json, "1.2.3"
    end
  end
end
