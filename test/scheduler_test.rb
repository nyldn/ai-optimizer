# frozen_string_literal: true

require "digest"
require_relative "test_helper"

class SchedulerTest < Minitest::Test
  def test_default_evening_schedule_round_trip_is_exact_and_idempotent
    in_tmpdir do |dir|
      plist_path = File.join(dir, "LaunchAgents", "io.github.nyldn.ai-optimizer.daily.plist")
      runner = TestSupport::FakeCommandRunner.new(
        "/bin/launchctl print gui/501/io.github.nyldn.ai-optimizer.daily" => { status: 1, stdout: "", stderr: "not found" },
        "/usr/bin/plutil -lint #{File.join(dir, "LaunchAgents", ".io.github.nyldn.ai-optimizer.daily.plist.tmp")}" => { status: 0, stdout: "OK", stderr: "" },
        "/bin/launchctl bootstrap gui/501 #{plist_path}" => { status: 0, stdout: "", stderr: "" },
        "/bin/launchctl bootout gui/501/io.github.nyldn.ai-optimizer.daily" => { status: 0, stdout: "", stderr: "" }
      )
      scheduler = AIOptimizer::Scheduler.new(
        launch_agents_dir: File.join(dir, "LaunchAgents"),
        data_dir: File.join(dir, "data"),
        executable: "/usr/local/bin/ai-optimizer",
        uid: 501,
        runner: runner
      )

      scheduler.schedule(hour: 21, minute: 0)
      plist = File.read(scheduler.plist_path)
      assert_includes plist, "io.github.nyldn.ai-optimizer.daily"
      assert_includes plist, "<integer>21</integer>"
      refute_includes plist, "com.chris"
      wrapper_digest = Digest::SHA256.hexdigest("/usr/local/bin/ai-optimizer")[0, 12]
      wrapper_path = File.join(dir, "data", "bin", "ai-optimizer-maintenance-v1-#{wrapper_digest}")
      expected_program = %r{<key>ProgramArguments</key>\s*<array>\s*<string>#{Regexp.escape(wrapper_path)}</string>\s*</array>}
      assert_match expected_program, plist
      refute_includes plist, "AI_OPTIMIZER_EXECUTABLE"
      refute_includes plist, "/usr/local/bin/ai-optimizer"
      assert_equal "#!/bin/sh\nexec '/usr/local/bin/ai-optimizer' run-maintenance\n", File.read(wrapper_path)
      assert_equal 0o700, File.stat(File.dirname(wrapper_path)).mode & 0o777
      assert_equal 0o700, File.stat(wrapper_path).mode & 0o777
      scheduler.schedule(hour: 21, minute: 0)
      assert File.file?(scheduler.plist_path)
      %w[daily.out.log daily.err.log].each do |name|
        log_path = File.join(dir, "data", "logs", name)
        assert File.file?(log_path)
        assert_equal 0o600, File.stat(log_path).mode & 0o777
      end
      scheduler.unschedule
      refute File.exist?(scheduler.plist_path)
    end
  end

  def test_schedule_secures_existing_logs_without_truncating_them
    in_tmpdir do |dir|
      agents = File.join(dir, "LaunchAgents")
      data_dir = File.join(dir, "data")
      log_dir = File.join(data_dir, "logs")
      FileUtils.mkdir_p(log_dir)
      log_path = File.join(log_dir, "daily.out.log")
      File.write(log_path, "retained receipt\n")
      File.chmod(0o644, log_path)
      plist_path = File.join(agents, "io.github.nyldn.ai-optimizer.daily.plist")
      runner = TestSupport::FakeCommandRunner.new(
        "/bin/launchctl print gui/501/io.github.nyldn.ai-optimizer.daily" => { status: 1, stdout: "", stderr: "not found" },
        "/usr/bin/plutil -lint #{File.join(agents, ".io.github.nyldn.ai-optimizer.daily.plist.tmp")}" => { status: 0, stdout: "OK", stderr: "" },
        "/bin/launchctl bootstrap gui/501 #{plist_path}" => { status: 0, stdout: "", stderr: "" }
      )
      scheduler = AIOptimizer::Scheduler.new(
        launch_agents_dir: agents, data_dir: data_dir,
        executable: "/usr/local/bin/ai-optimizer", uid: 501, runner: runner
      )

      scheduler.schedule(hour: 21, minute: 0)

      assert_equal "retained receipt\n", File.read(log_path)
      assert_equal 0o600, File.stat(log_path).mode & 0o777
      assert_equal 0o600, File.stat(File.join(log_dir, "daily.err.log")).mode & 0o777
    end
  end

  def test_schedule_refuses_a_symlinked_log_file
    in_tmpdir do |dir|
      data_dir = File.join(dir, "data")
      log_dir = File.join(data_dir, "logs")
      FileUtils.mkdir_p(log_dir)
      external = File.join(dir, "external.log")
      File.write(external, "must remain unchanged\n")
      File.symlink(external, File.join(log_dir, "daily.out.log"))
      scheduler = AIOptimizer::Scheduler.new(
        launch_agents_dir: File.join(dir, "agents"), data_dir: data_dir,
        executable: "/usr/local/bin/ai-optimizer", uid: 501,
        runner: TestSupport::FakeCommandRunner.new
      )

      assert_raises(AIOptimizer::OwnershipError) { scheduler.schedule(hour: 21, minute: 0) }
      assert_equal "must remain unchanged\n", File.read(external)
    end
  end

  def test_schedule_refuses_a_symlinked_maintenance_launcher
    in_tmpdir do |dir|
      data_dir = File.join(dir, "data")
      bin_dir = File.join(data_dir, "bin")
      FileUtils.mkdir_p(bin_dir)
      external = File.join(dir, "external-launcher")
      File.write(external, "must remain unchanged\n")
      executable = "/usr/local/bin/ai-optimizer"
      wrapper_digest = Digest::SHA256.hexdigest(executable)[0, 12]
      wrapper_path = File.join(bin_dir, "ai-optimizer-maintenance-v1-#{wrapper_digest}")
      File.symlink(external, wrapper_path)
      scheduler = AIOptimizer::Scheduler.new(
        launch_agents_dir: File.join(dir, "agents"), data_dir: data_dir,
        executable: executable, uid: 501,
        runner: TestSupport::FakeCommandRunner.new
      )

      assert_raises(AIOptimizer::OwnershipError) { scheduler.schedule(hour: 21, minute: 0) }
      assert_equal "must remain unchanged\n", File.read(external)
    end
  end

  def test_maintenance_launcher_executes_the_exact_configured_path
    in_tmpdir do |dir|
      agents = File.join(dir, "agents")
      executable_dir = File.join(dir, "tool's bin-José")
      FileUtils.mkdir_p(executable_dir)
      executable = File.join(executable_dir, "ai optimizer")
      File.write(executable, "#!/bin/sh\nprintf '%s' \"$1\"\n")
      File.chmod(0o700, executable)
      plist_path = File.join(agents, "io.github.nyldn.ai-optimizer.daily.plist")
      runner = TestSupport::FakeCommandRunner.new(
        "/bin/launchctl print gui/501/io.github.nyldn.ai-optimizer.daily" => { status: 1, stdout: "", stderr: "not found" },
        "/usr/bin/plutil -lint #{File.join(agents, ".io.github.nyldn.ai-optimizer.daily.plist.tmp")}" => { status: 0, stdout: "OK", stderr: "" },
        "/bin/launchctl bootstrap gui/501 #{plist_path}" => { status: 0, stdout: "", stderr: "" }
      )
      scheduler = AIOptimizer::Scheduler.new(
        launch_agents_dir: agents, data_dir: File.join(dir, "data"),
        executable: executable, uid: 501, runner: runner
      )

      scheduler.schedule(hour: 21, minute: 0)
      scheduler.schedule(hour: 21, minute: 0)

      wrapper_digest = Digest::SHA256.hexdigest(executable)[0, 12]
      wrapper_path = File.join(dir, "data", "bin", "ai-optimizer-maintenance-v1-#{wrapper_digest}")
      stdout, stderr, status = Open3.capture3(wrapper_path)
      assert status.success?, stderr
      assert_equal "run-maintenance", stdout
    end
  end

  def test_schedule_refuses_a_drifted_maintenance_launcher
    in_tmpdir do |dir|
      data_dir = File.join(dir, "data")
      bin_dir = File.join(data_dir, "bin")
      FileUtils.mkdir_p(bin_dir)
      executable = "/usr/local/bin/ai-optimizer"
      wrapper_digest = Digest::SHA256.hexdigest(executable)[0, 12]
      wrapper_path = File.join(bin_dir, "ai-optimizer-maintenance-v1-#{wrapper_digest}")
      File.write(wrapper_path, "unowned content\n")
      scheduler = AIOptimizer::Scheduler.new(
        launch_agents_dir: File.join(dir, "agents"), data_dir: data_dir,
        executable: executable, uid: 501,
        runner: TestSupport::FakeCommandRunner.new
      )

      assert_raises(AIOptimizer::OwnershipError) { scheduler.schedule(hour: 21, minute: 0) }
      assert_equal "unowned content\n", File.read(wrapper_path)
    end
  end

  def test_rejects_outside_window_without_explicit_override
    in_tmpdir do |dir|
      scheduler = AIOptimizer::Scheduler.new(
        launch_agents_dir: File.join(dir, "agents"), data_dir: File.join(dir, "data"),
        executable: "/tmp/ai-optimizer", uid: 501,
        runner: TestSupport::FakeCommandRunner.new
      )
      assert_raises(AIOptimizer::UsageError) { scheduler.schedule(hour: 10, minute: 0) }
    end
  end

  def test_runtime_guard_writes_skip_receipt_outside_evening_window
    in_tmpdir do |dir|
      receipt = AIOptimizer::Maintenance.new(data_dir: dir, clock: -> { Time.local(2026, 8, 22, 10, 0, 0) }).run
      assert_equal "skipped_outside_window", receipt.fetch("status")
      assert_equal receipt, JSON.parse(File.read(File.join(dir, "reports", "latest-run.json")))
    end
  end

  def test_failed_bootout_preserves_previous_plist
    in_tmpdir do |dir|
      agents = File.join(dir, "LaunchAgents")
      FileUtils.mkdir_p(agents)
      plist_path = File.join(agents, "io.github.nyldn.ai-optimizer.daily.plist")
      previous = "<string>io.github.nyldn.ai-optimizer.daily</string><string>run-maintenance</string>"
      File.write(plist_path, previous)
      runner = TestSupport::FakeCommandRunner.new(
        "/usr/bin/plutil -lint #{File.join(agents, ".io.github.nyldn.ai-optimizer.daily.plist.tmp")}" => { status: 0, stdout: "OK", stderr: "" },
        "/bin/launchctl print gui/501/io.github.nyldn.ai-optimizer.daily" => { status: 0, stdout: "loaded", stderr: "" },
        "/bin/launchctl bootout gui/501/io.github.nyldn.ai-optimizer.daily" => { status: 5, stdout: "", stderr: "failed" }
      )
      scheduler = AIOptimizer::Scheduler.new(
        launch_agents_dir: agents, data_dir: File.join(dir, "data"),
        executable: "/usr/local/bin/ai-optimizer", uid: 501, runner: runner
      )

      assert_raises(AIOptimizer::InternalError) { scheduler.schedule(hour: 21, minute: 0) }
      assert_equal previous, File.read(plist_path)
    end
  end

  def test_failed_bootstrap_restores_previous_plist
    in_tmpdir do |dir|
      agents = File.join(dir, "LaunchAgents")
      FileUtils.mkdir_p(agents)
      plist_path = File.join(agents, "io.github.nyldn.ai-optimizer.daily.plist")
      previous = "<string>io.github.nyldn.ai-optimizer.daily</string><string>run-maintenance</string>"
      File.write(plist_path, previous)
      runner = TestSupport::FakeCommandRunner.new(
        "/usr/bin/plutil -lint #{File.join(agents, ".io.github.nyldn.ai-optimizer.daily.plist.tmp")}" => { status: 0, stdout: "OK", stderr: "" },
        "/bin/launchctl print gui/501/io.github.nyldn.ai-optimizer.daily" => { status: 1, stdout: "", stderr: "not loaded" },
        "/bin/launchctl bootstrap gui/501 #{plist_path}" => { status: 5, stdout: "", stderr: "failed" }
      )
      scheduler = AIOptimizer::Scheduler.new(
        launch_agents_dir: agents, data_dir: File.join(dir, "data"),
        executable: "/usr/local/bin/ai-optimizer", uid: 501, runner: runner
      )

      assert_raises(AIOptimizer::InternalError) { scheduler.schedule(hour: 21, minute: 0) }
      assert_equal previous, File.read(plist_path)
    end
  end
end
