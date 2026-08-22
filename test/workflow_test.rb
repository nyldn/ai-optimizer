# frozen_string_literal: true

require_relative "test_helper"

class WorkflowTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def test_actions_are_pinned_to_full_commit_shas
    workflows.each do |path, content|
      content.scan(/^\s*uses:\s*([^\s#]+)/).flatten.each do |reference|
        assert_match(/\A[^@]+@[0-9a-f]{40}\z/, reference, "unpinned action in #{path}: #{reference}")
      end
    end
  end

  def test_ci_uses_current_intel_and_apple_silicon_runners
    content = File.read(File.join(ROOT, ".github", "workflows", "ci.yml"))
    assert_includes content, "macos-15-intel"
    assert_includes content, "macos-15"
  end

  def test_release_write_permissions_are_explicit_and_narrow
    content = File.read(File.join(ROOT, ".github", "workflows", "release.yml"))
    assert_includes content, "contents: read"
    assert_equal 1, content.scan(/^\s{6}contents: write$/).length
    assert_equal 1, content.scan(/^\s{6}id-token: write$/).length
    assert_equal 1, content.scan(/^\s{6}attestations: write$/).length
    refute_match(/pull_request_target/, content)
  end

  private

  def workflows
    Dir[File.join(ROOT, ".github", "workflows", "*.yml")].sort.map do |path|
      [path, File.read(path)]
    end
  end
end
