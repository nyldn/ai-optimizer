# frozen_string_literal: true

require "cgi"
require "digest"
require "fileutils"

module AIOptimizer
  class Scheduler
    LABEL = "io.github.nyldn.ai-optimizer.daily"
    LOG_FILES = %w[daily.out.log daily.err.log].freeze
    WRAPPER_NAME = "ai-optimizer-maintenance-v1"

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
      secure_log_files
      write_maintenance_wrapper

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
      versioned_wrapper = %r{/#{Regexp.escape(WRAPPER_NAME)}-[0-9a-f]{12}</string>}
      command_owned = content.include?("<string>run-maintenance</string>") ||
                      content.include?("/ai-optimizer-maintenance</string>") ||
                      content.match?(versioned_wrapper)
      owned = content.include?("<string>#{LABEL}</string>") && command_owned
      raise OwnershipError, "existing launch agent is not provably owned by AI Environment Optimizer" unless owned
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

    def secure_log_files
      raise OwnershipError, "data directory must not be a symlink" if File.symlink?(data_dir)

      log_dir = File.join(data_dir, "logs")
      raise OwnershipError, "log directory must not be a symlink" if File.symlink?(log_dir)

      FileUtils.mkdir_p(log_dir, mode: 0o700)
      File.chmod(0o700, log_dir)
      LOG_FILES.each do |name|
        path = File.join(log_dir, name)
        raise OwnershipError, "refusing to use a symlinked log file" if File.symlink?(path)

        flags = File::WRONLY | File::CREAT | File::APPEND | File::NOFOLLOW
        File.open(path, flags, 0o600) { |file| file.chmod(0o600) }
      end
    rescue Errno::ELOOP
      raise OwnershipError, "refusing to use a symlinked log file"
    end

    def maintenance_wrapper_path
      digest = Digest::SHA256.hexdigest(executable)[0, 12]
      File.join(data_dir, "bin", "#{WRAPPER_NAME}-#{digest}")
    end

    def maintenance_wrapper_content
      "#!/bin/sh\nexec #{shell_quote(executable)} run-maintenance\n"
    end

    def shell_quote(value)
      "'#{value.gsub("'", %q('"'"'))}'"
    end

    def write_maintenance_wrapper
      bin_dir = File.dirname(maintenance_wrapper_path)
      raise OwnershipError, "maintenance bin directory must not be a symlink" if File.symlink?(bin_dir)
      raise OwnershipError, "refusing to replace a symlinked maintenance launcher" if File.symlink?(maintenance_wrapper_path)

      FileUtils.mkdir_p(bin_dir, mode: 0o700)
      File.chmod(0o700, bin_dir)
      if File.exist?(maintenance_wrapper_path)
        existing = File.file?(maintenance_wrapper_path) && File.binread(maintenance_wrapper_path)
        expected = maintenance_wrapper_content.dup.force_encoding(Encoding::BINARY)
        raise OwnershipError, "existing maintenance launcher does not match AI Environment Optimizer" unless existing == expected

        File.chmod(0o700, maintenance_wrapper_path)
        return
      end

      temporary = File.join(bin_dir, ".#{File.basename(maintenance_wrapper_path)}.#{Process.pid}.tmp")
      File.open(temporary, File::WRONLY | File::CREAT | File::EXCL, 0o700) do |file|
        file.write(maintenance_wrapper_content)
        file.flush
        file.fsync
      end
      File.chmod(0o700, temporary)
      File.rename(temporary, maintenance_wrapper_path)
    ensure
      FileUtils.rm_f(temporary) if defined?(temporary) && temporary && File.exist?(temporary)
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
            <string>#{escape(maintenance_wrapper_path)}</string>
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
            <key>AI_ENV_OPTIMIZER_DATA_DIR</key>
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
