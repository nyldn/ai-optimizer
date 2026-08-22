# frozen_string_literal: true

require "open3"
require "timeout"

module AIOptimizer
  CommandResult = Struct.new(:command, :status, :stdout, :stderr, :timed_out, :duration) do
    def success?
      status == 0 && !timed_out
    end

    def to_h
      {
        command: command,
        status: status,
        timed_out: timed_out,
        duration: duration
      }
    end
  end

  class CommandRunner
    def run(argv, timeout: 10, env: {})
      raise ArgumentError, "command must be a non-empty argument array" unless argv.is_a?(Array) && !argv.empty?

      started = monotonic_time
      stdout_text = ""
      stderr_text = ""
      status = nil
      timed_out = false

      Open3.popen3(env, *argv, pgroup: true) do |stdin, stdout, stderr, wait_thread|
        stdin.close
        stdout_reader = Thread.new { stdout.read }
        stderr_reader = Thread.new { stderr.read }
        begin
          Timeout.timeout(timeout) { status = wait_thread.value.exitstatus }
        rescue Timeout::Error
          timed_out = true
          terminate_process_group(wait_thread.pid)
          status = 124
        ensure
          stdout_text = stdout_reader.value
          stderr_text = stderr_reader.value
        end
      end

      CommandResult.new(
        File.basename(argv.first.to_s),
        status,
        Redactor.scrub(stdout_text),
        Redactor.scrub(stderr_text),
        timed_out,
        (monotonic_time - started).round(3)
      )
    rescue Errno::ENOENT => error
      CommandResult.new(
        File.basename(argv.first.to_s),
        127,
        "",
        Redactor.scrub(error.message),
        false,
        (monotonic_time - started).round(3)
      )
    end

    private

    def monotonic_time
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def terminate_process_group(pid)
      Process.kill("TERM", -pid)
      sleep 0.02
      Process.kill("KILL", -pid)
    rescue Errno::ESRCH
      nil
    ensure
      begin
        Process.wait(pid)
      rescue Errno::ECHILD, Errno::ESRCH
        nil
      end
    end
  end
end
