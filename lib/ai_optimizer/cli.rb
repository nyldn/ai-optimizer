# frozen_string_literal: true

require "json"
require "optparse"
require "rbconfig"

module AIOptimizer
  class CLI
    HELP = <<~HELP
      AI Environment Optimizer keeps a macOS Claude Code and Codex environment understandable.

      Usage:
        ai-env-optimizer setup [--workspace-root PATH] [--schedule]
        ai-env-optimizer doctor [--json] [--strict]
        ai-env-optimizer scan [--json] [--strict] [--workspace-root PATH]
        ai-env-optimizer agent-context [--json] [--strict] [--workspace-root PATH]
        ai-env-optimizer storage [--json] [--strict]
        ai-env-optimizer report [--json]
        ai-env-optimizer schedule [--hour H] [--minute M] [--force-outside-window]
        ai-env-optimizer schedule status
        ai-env-optimizer unschedule
        ai-env-optimizer version
        ai-env-optimizer help

      doctor, scan, and agent-context are read-only. Scheduling is opt-in and owns only:
        #{Scheduler::LABEL}
    HELP

    def self.start(argv, stdout: $stdout, stderr: $stderr, env: ENV)
      new(stdout: stdout, stderr: stderr, env: env).run(argv)
    rescue UsageError, OptionParser::ParseError => error
      stderr.puts("Usage error: #{error.message}")
      stderr.puts(HELP)
      2
    rescue StandardError => error
      stderr.puts("AI Environment Optimizer could not complete: #{Redactor.scrub(error.message)}")
      3
    end

    def initialize(stdout:, stderr:, env:)
      @stdout = stdout
      @stderr = stderr
      @env = env
    end

    def run(argv)
      args = argv.dup
      command = args.shift || "help"
      case command
      when "help", "-h", "--help"
        @stdout.write(HELP)
        0
      when "version", "--version"
        @stdout.puts("ai-env-optimizer #{VERSION}")
        0
      when "doctor"
        run_diagnostic(args, Doctor)
      when "scan"
        run_diagnostic(args, Scanner)
      when "agent-context"
        run_agent_context(args)
      when "storage"
        run_storage(args)
      when "setup"
        run_setup(args)
      when "schedule"
        run_schedule(args)
      when "unschedule"
        require_no_args(args)
        update_schedule(false) { scheduler.unschedule }
      when "report"
        run_report(args)
      when "run-maintenance"
        require_no_args(args)
        run_maintenance
      else
        raise UsageError, "unknown command: #{command}"
      end
    end

    private

    def run_diagnostic(args, engine_class)
      options = { json: false, strict: false, workspace_root: nil }
      parser = OptionParser.new do |opts|
        opts.on("--json") { options[:json] = true }
        opts.on("--strict") { options[:strict] = true }
        if engine_class == Scanner
          opts.on("--workspace-root PATH") { |path| options[:workspace_root] = path }
        end
      end
      parser.parse!(args)
      require_no_args(args)

      report = engine_class.new(build_context(options[:workspace_root])).run
      @stdout.write(options[:json] ? report.to_json + "\n" : report.to_text)
      report.exit_code(strict: options[:strict])
    end

    def run_setup(args)
      options = { workspace_root: nil, schedule: false }
      parser = OptionParser.new do |opts|
        opts.on("--workspace-root PATH") { |path| options[:workspace_root] = path }
        opts.on("--schedule") { options[:schedule] = true }
      end
      parser.parse!(args)
      require_no_args(args)

      workspace_root = File.expand_path(options[:workspace_root] || config.default_workspace_root)
      raise UsageError, "workspace root must be an existing directory" unless Dir.exist?(workspace_root)

      values = config.defaults.merge("workspace_root" => workspace_root)
      @stdout.puts("AI Environment Optimizer will create:")
      @stdout.puts("  #{display_path(config.path)}")
      @stdout.puts("Workspace root: #{display_path(workspace_root)}")
      config.save(values)
      if options[:schedule]
        scheduler.schedule(hour: 21, minute: 0)
        values["schedule"] = { "enabled" => true, "hour" => 21, "minute" => 0 }
        config.save(values)
        @stdout.puts("Evening doctor scheduled for 21:00 local time.")
      end
      @stdout.puts("Ready. Run: ai-env-optimizer doctor")
      0
    end

    def run_storage(args)
      if args.first == "cleanup"
        args.shift
        return run_storage_cleanup(args)
      end

      options = { json: false, strict: false }
      parser = OptionParser.new do |opts|
        opts.on("--json") { options[:json] = true }
        opts.on("--strict") { options[:strict] = true }
      end
      parser.parse!(args)
      require_no_args(args)

      report = build_storage_report
      @stdout.write(options[:json] ? report.to_json + "\n" : report.to_text)
      report.exit_code(strict: options[:strict])
    end

    def run_storage_cleanup(args)
      options = {
        json: false,
        older_than_days: CleanupPlanner::DEFAULT_OLDER_THAN_DAYS,
        min_size_mb: CleanupPlanner::DEFAULT_MIN_SIZE_MB
      }
      parser = OptionParser.new do |opts|
        opts.on("--dry-run") { nil }
        opts.on("--older-than DAYS", Integer) { |value| options[:older_than_days] = value }
        opts.on("--min-size MB", Integer) { |value| options[:min_size_mb] = value }
        opts.on("--json") { options[:json] = true }
      end
      parser.parse!(args)
      require_no_args(args)

      catalog = build_storage_catalog
      plan = CleanupPlanner.new(
        sources: catalog.sources,
        home: home_dir,
        data_dir: data_dir
      ).preview(
        older_than_days: options[:older_than_days],
        min_size_mb: options[:min_size_mb]
      )
      if options[:json]
        @stdout.puts(JSON.generate(plan.to_h))
      else
        summary = plan.to_h.fetch("summary")
        @stdout.puts("Cleanup preview: #{summary.fetch("candidate_files")} files, #{summary.fetch("allocated_bytes")} allocated bytes")
        @stdout.puts("Token: #{plan.token}")
        @stdout.puts(
          "Apply: ai-env-optimizer storage cleanup --apply #{plan.token} " \
          "--older-than #{plan.older_than_days} --min-size #{plan.min_size_mb}"
        )
      end
      0
    end

    def run_agent_context(args)
      options = { json: false, strict: false, workspace_root: nil }
      parser = OptionParser.new do |opts|
        opts.on("--json") { options[:json] = true }
        opts.on("--strict") { options[:strict] = true }
        opts.on("--workspace-root PATH") { |path| options[:workspace_root] = path }
      end
      parser.parse!(args)
      require_no_args(args)

      context = build_context(options[:workspace_root])
      agent_context = AgentContext.new(
        doctor_report: Doctor.new(context).run,
        scan_report: Scanner.new(context).run
      )
      @stdout.write(options[:json] ? agent_context.to_json + "\n" : agent_context.to_text)
      agent_context.exit_code(strict: options[:strict])
    end

    def run_schedule(args)
      if args.first == "status"
        args.shift
        require_no_args(args)
        state = scheduler.status
        @stdout.puts(state["loaded"] ? "scheduled and loaded" : "not loaded")
        @stdout.puts("plist: #{state["plist_present"] ? "present" : "absent"}")
        return 0
      end

      options = { hour: 21, minute: 0, force: false }
      parser = OptionParser.new do |opts|
        opts.on("--hour H", Integer) { |value| options[:hour] = value }
        opts.on("--minute M", Integer) { |value| options[:minute] = value }
        opts.on("--force-outside-window") { options[:force] = true }
      end
      parser.parse!(args)
      require_no_args(args)
      state = scheduler.schedule(
        hour: options[:hour],
        minute: options[:minute],
        force_outside_window: options[:force]
      )
      values = config.load
      values["schedule"] = {
        "enabled" => true,
        "hour" => options[:hour],
        "minute" => options[:minute]
      }
      config.save(values)
      @stdout.puts("Scheduled #{state.fetch("label")} at #{format("%02d:%02d", options[:hour], options[:minute])} local time.")
      0
    end

    def update_schedule(enabled)
      yield
      values = config.load
      current = values.fetch("schedule", {})
      values["schedule"] = current.merge("enabled" => enabled)
      config.save(values)
      @stdout.puts(enabled ? "Schedule enabled." : "Schedule removed.")
      0
    end

    def run_report(args)
      options = { json: false }
      OptionParser.new { |opts| opts.on("--json") { options[:json] = true } }.parse!(args)
      require_no_args(args)
      path = File.join(data_dir, "reports", "latest-run.json")
      unless File.file?(path) && !File.symlink?(path)
        @stdout.puts(options[:json] ? JSON.generate("status" => "no_report") : "No scheduled-run report yet.")
        return 0
      end
      payload = JSON.parse(File.binread(path))
      if options[:json]
        @stdout.puts(JSON.generate(payload))
      else
        @stdout.puts("Latest maintenance: #{payload.fetch("status", "unknown")}")
        @stdout.puts("Generated: #{payload.fetch("generated_at", "unknown")}")
      end
      payload.fetch("exit_code", 0).to_i
    rescue JSON::ParserError
      raise InternalError, "latest report is invalid"
    end

    def run_maintenance
      maintenance = Maintenance.new(
        data_dir: data_dir,
        doctor: -> { Scanner.new(build_context(nil)).run }
      )
      receipt = maintenance.run
      @stdout.puts(JSON.generate(receipt))
      receipt.fetch("exit_code")
    end

    def build_context(workspace_override)
      runner = CommandRunner.new
      values = begin
        config.load
      rescue ConfigError, OwnershipError
        config.defaults
      end
      workspace_root = File.expand_path(workspace_override || values.fetch("workspace_root"))
      architecture_result = runner.run(["/usr/bin/uname", "-m"], timeout: 3)
      version_result = runner.run(["/usr/bin/sw_vers", "-productVersion"], timeout: 3)
      CheckContext.new(
        home: Dir.home,
        data_dir: data_dir,
        workspace_root: workspace_root,
        path: @env.fetch("PATH", ""),
        runner: runner,
        platform: RbConfig::CONFIG.fetch("host_os", ""),
        architecture: architecture_result.success? ? architecture_result.stdout.strip : "unknown",
        macos_version: version_result.success? ? version_result.stdout.strip : "0"
      )
    end

    def build_storage_report
      catalog = build_storage_catalog
      measurements = StorageScanner.new(
        sources: catalog.sources,
        home: home_dir,
        data_dir: data_dir
      ).scan
      StorageReport.new(measurements)
    end

    def build_storage_catalog
      StorageCatalog.new(home: home_dir, data_dir: data_dir)
    end

    def home_dir
      @home_dir ||= File.expand_path(@env["HOME"] || Dir.home)
    end

    def config
      @config ||= Config.new(data_dir: data_dir)
    end

    def data_dir
      @data_dir ||= File.expand_path(
        env_value("AI_ENV_OPTIMIZER_DATA_DIR", "AI_OPTIMIZER_DATA_DIR") || Config.default_data_dir
      )
    end

    def scheduler
      @scheduler ||= Scheduler.new(
        launch_agents_dir: File.expand_path(
          env_value("AI_ENV_OPTIMIZER_LAUNCH_AGENTS_DIR", "AI_OPTIMIZER_LAUNCH_AGENTS_DIR") ||
            File.join(Dir.home, "Library", "LaunchAgents")
        ),
        data_dir: data_dir,
        executable: executable_path,
        uid: Process.uid
      )
    end

    def executable_path
      program = $PROGRAM_NAME
      return File.expand_path(program) if program.include?(File::SEPARATOR)

      @env.fetch("PATH", "").split(File::PATH_SEPARATOR).each do |directory|
        candidate = File.join(directory, program)
        return File.expand_path(candidate) if File.file?(candidate) && File.executable?(candidate)
      end
      File.expand_path(program)
    end

    def require_no_args(args)
      raise UsageError, "unexpected arguments: #{args.length}" unless args.empty?
    end

    def env_value(canonical, legacy)
      @env[canonical] || @env[legacy]
    end

    def display_path(path)
      Redactor.scrub(path, home: Dir.home)
    end
  end
end
