# frozen_string_literal: true

require "cgi"
require "fileutils"

module AIOptimizer
  class Scheduler
    LABEL = "io.github.nyldn.ai-optimizer.daily"

    attr_reader :launch_agents_dir, :data_dir, :executable, :uid, :runner

    def initialize(launch_agents_dir:, data_dir:, executable:, uid:, runner: CommandRunner.new)
      @launch_agents_dir = File.expand_path(launch_agents_dir)
      @data_dir = File.expand_path(data_dir)
      @executable = File.expand_path(executable)
      @uid = Integer(uid)
      @runner = runner
    end

    def plist_path
      File.join(launch_agents_dir, "#{LABEL}.plist")
    end

    def schedule(hour: 21, minute: 0, force_outside_window: false)
      hour = Integer(hour)
      minute = Integer(minute)
      validate_time(hour, minute, force_outside_window)
      ensure_owned_paths
      FileUtils.mkdir_p(launch_agents_dir, mode: 0o700)
      FileUtils.mkdir_p(File.join(data_dir, "logs"), mode: 0o700)

      previous_content = File.file?(plist_path) ? File.binread(plist_path) : nil

      temporary = File.join(launch_agents_dir, ".#{LABEL}.plist.tmp")
      File.open(temporary, File::WRONLY | File::CREAT | File::TRUNC, 0o600) do |file|
        file.write(plist(hour, minute))
        file.flush
        file.fsync
      end
      validation = runner.run(["/usr/bin/plutil", "-lint", temporary], timeout: 5)
      raise InternalError, "generated launchd plist failed validation" unless validation.success?

      was_loaded = loaded?
      if was_loaded
        bootout = runner.run(["/bin/launchctl", "bootout", service_target], timeout: 10)
        raise InternalError, "launchd bootout failed; previous schedule was preserved" unless bootout.success?
      end
      File.rename(temporary, plist_path)
      result = runner.run(["/bin/launchctl", "bootstrap", domain_target, plist_path], timeout: 10)
      unless result.success?
        restore_previous_plist(previous_content, temporary)
        runner.run(["/bin/launchctl", "bootstrap", domain_target, plist_path], timeout: 10) if was_loaded && previous_content
        raise InternalError, "launchd bootstrap failed; previous schedule was restored"
      end

      { "label" => LABEL, "hour" => hour, "minute" => minute, "loaded" => true }
    ensure
      FileUtils.rm_f(temporary) if defined?(temporary) && temporary && File.exist?(temporary)
    end

    def status
      {
        "label" => LABEL,
        "plist_present" => File.file?(plist_path) && !File.symlink?(plist_path),
        "loaded" => loaded?
      }
    end

    def unschedule
      ensure_owned_paths
      if loaded?
        result = runner.run(["/bin/launchctl", "bootout", service_target], timeout: 10)
        raise InternalError, "launchd bootout failed; plist was preserved" unless result.success?
      end
      FileUtils.rm_f(plist_path)
      { "label" => LABEL, "loaded" => false, "plist_present" => false }
    end

    def self.inside_window?(time)
      time.hour >= 19 || time.hour < 2 || (time.hour == 2 && time.min.zero?)
    end

    private

    def validate_time(hour, minute, force)
      raise UsageError, "hour must be between 0 and 23" unless hour.between?(0, 23)
      raise UsageError, "minute must be between 0 and 59" unless minute.between?(0, 59)
      scheduled = Time.local(2026, 1, 1, hour, minute, 0)
      return if force || self.class.inside_window?(scheduled)

      raise UsageError, "schedule must be between 19:00 and 02:00 local time"
    end

    def ensure_owned_paths
      raise OwnershipError, "LaunchAgents directory must not be a symlink" if File.symlink?(launch_agents_dir)
      raise OwnershipError, "refusing to replace a symlinked launch agent" if File.symlink?(plist_path)
      return unless File.file?(plist_path)

      content = File.binread(plist_path, 64_000)
      owned = content.include?("<string>#{LABEL}</string>") && content.include?("<string>run-maintenance</string>")
      raise OwnershipError, "existing launch agent is not provably owned by AI Optimizer" unless owned
    end

    def restore_previous_plist(previous_content, temporary)
      if previous_content
        File.open(temporary, File::WRONLY | File::CREAT | File::TRUNC, 0o600) do |file|
          file.write(previous_content)
          file.flush
          file.fsync
        end
        File.rename(temporary, plist_path)
      else
        FileUtils.rm_f(plist_path)
      end
    end

    def loaded?
      runner.run(["/bin/launchctl", "print", service_target], timeout: 5).success?
    end

    def domain_target
      "gui/#{uid}"
    end

    def service_target
      "#{domain_target}/#{LABEL}"
    end

    def plist(hour, minute)
      log_dir = File.join(data_dir, "logs")
      <<~PLIST
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>Label</key>
          <string>#{LABEL}</string>
          <key>ProgramArguments</key>
          <array>
            <string>#{escape(executable)}</string>
            <string>run-maintenance</string>
          </array>
          <key>StartCalendarInterval</key>
          <dict>
            <key>Hour</key>
            <integer>#{hour}</integer>
            <key>Minute</key>
            <integer>#{minute}</integer>
          </dict>
          <key>ProcessType</key>
          <string>Background</string>
          <key>EnvironmentVariables</key>
          <dict>
            <key>PATH</key>
            <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
            <key>AI_OPTIMIZER_DATA_DIR</key>
            <string>#{escape(data_dir)}</string>
          </dict>
          <key>StandardOutPath</key>
          <string>#{escape(File.join(log_dir, "daily.out.log"))}</string>
          <key>StandardErrorPath</key>
          <string>#{escape(File.join(log_dir, "daily.err.log"))}</string>
        </dict>
        </plist>
      PLIST
    end

    def escape(value)
      CGI.escapeHTML(value.to_s)
    end
  end
end
