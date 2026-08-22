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
end
