# frozen_string_literal: true

require_relative "test_helper"

class ScriptTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def test_scripts_and_workflows_have_no_patch_continuation_artifacts
    paths = Dir[File.join(ROOT, "**", "*.sh")] +
            Dir[File.join(ROOT, ".github", "workflows", "*.yml")]
    paths.each do |path|
      refute_match(/\s\+\s{2,}/, File.read(path), "patch marker artifact in #{path}")
    end
  end

  def test_codex_and_claude_entrypoints_share_the_agent_context_handshake
    agents = File.read(File.join(ROOT, "AGENTS.md"))
    claude = File.read(File.join(ROOT, "CLAUDE.md"))

    assert_includes agents, "./bin/ai-env-optimizer agent-context --json"
    assert_includes agents, "Operator workflow"
    assert_includes agents, "Development workflow"
    assert_includes claude, "AGENTS.md"
    assert_includes claude, "./bin/ai-env-optimizer agent-context --json"
    assert_includes File.read(File.join(ROOT, "docs", "architecture.md")), "Agent context"
    assert_includes File.read(File.join(ROOT, "docs", "privacy.md")), "`doctor`, `scan`, and `agent-context` do not write"
  end


  def test_release_and_install_surfaces_use_the_canonical_name
    build = File.read(File.join(ROOT, "scripts", "build-release.sh"))
    install = File.read(File.join(ROOT, "install.sh"))
    release = File.read(File.join(ROOT, ".github", "workflows", "release.yml"))

    assert_includes build, 'ARCHIVE="ai-env-optimizer-${VERSION}.tar.gz"'
    assert_includes install, "github.com/nyldn/ai-env-optimizer"
    assert_includes release, "dist/ai-env-optimizer-*.tar.gz"
    assert File.executable?(File.join(ROOT, "bin", "ai-env-optimizer"))
    refute File.exist?(File.join(ROOT, "bin", "ai-optimizer"))
  end
end
