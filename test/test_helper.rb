# frozen_string_literal: true

require "fileutils"
require "json"
require "minitest/autorun"
require "open3"
require "tmpdir"

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "ai_optimizer"

module TestSupport
  def in_tmpdir
    Dir.mktmpdir("ai-optimizer-test-") do |dir|
      yield dir
    end
  end

  class FakeCommandRunner
    attr_reader :calls

    def initialize(results = {})
      @results = results
      @calls = []
    end

    def run(argv, timeout: 10, env: {})
      @calls << { argv: argv, timeout: timeout, env: env }
      key = argv.join(" ")
      result = @results.fetch(key, { stdout: "", stderr: "", status: 0 })
      AIOptimizer::CommandResult.new(
        File.basename(argv.first),
        result[:status],
        result[:stdout],
        result[:stderr],
        result.fetch(:timed_out, false),
        result.fetch(:duration, 0.01)
      )
    end
  end
end

class Minitest::Test
  include TestSupport
end
