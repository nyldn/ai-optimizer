# frozen_string_literal: true

require "fileutils"
require "json"
require "time"

module AIOptimizer
  class Maintenance
    attr_reader :data_dir

    def initialize(data_dir:, clock: -> { Time.now }, doctor: nil, storage: nil,
                   warning_bytes: Config::DEFAULT_STORAGE_WARNING_BYTES)
      @data_dir = File.expand_path(data_dir)
      @clock = clock
      @doctor = doctor
      @storage = storage
      @warning_bytes = if warning_bytes.is_a?(Integer) && warning_bytes.positive?
                         warning_bytes
                       else
                         Config::DEFAULT_STORAGE_WARNING_BYTES
                       end
    end

    def run
      time = @clock.call
      receipt = if Scheduler.inside_window?(time)
                  run_doctor(time)
                else
                  base_receipt(time).merge(
                    "status" => "skipped_outside_window",
                    "exit_code" => 0,
                    "summary" => {}
                  )
                end
      write_receipt(receipt)
      receipt
    rescue StandardError
      time ||= Time.now
      receipt = base_receipt(time).merge(
        "status" => "unknown",
        "exit_code" => 3,
        "summary" => {}
      )
      write_receipt(receipt)
      receipt
    end

    private

    def run_doctor(time)
      report = @doctor.call
      code = report.exit_code
      receipt = base_receipt(time).merge(
        "status" => code.zero? ? "passed" : "failed",
        "exit_code" => code,
        "summary" => report.summary
      )
      @storage ? receipt.merge("storage" => storage_summary) : receipt
    end

    def base_receipt(time)
      {
        "schema_version" => 1,
        "product" => "ai-env-optimizer",
        "compatibility" => { "legacy_names" => ["ai-optimizer"] },
        "generated_at" => time.utc.iso8601
      }
    end

    def storage_summary
      summary = @storage.call.summary
      allocated = nonnegative_integer(summary, "allocated_bytes")
      {
        "status" => allocated >= @warning_bytes ? "warning" : "healthy",
        "allocated_bytes" => allocated,
        "protected_bytes" => nonnegative_integer(summary, "protected_bytes"),
        "reclaimable_bytes" => nonnegative_integer(summary, "reclaimable_bytes"),
        "unknown_sources" => nonnegative_integer(summary, "unknown_sources")
      }
    end

    def nonnegative_integer(summary, key)
      value = summary.fetch(key)
      raise InternalError, "invalid storage summary" unless value.is_a?(Integer) && value >= 0

      value
    end

    def write_receipt(receipt)
      reports_dir = File.join(data_dir, "reports")
      raise OwnershipError, "reports directory must not be a symlink" if File.symlink?(reports_dir)

      FileUtils.mkdir_p(reports_dir, mode: 0o700)
      target = File.join(reports_dir, "latest-run.json")
      raise OwnershipError, "receipt path must not be a symlink" if File.symlink?(target)

      temporary = File.join(reports_dir, ".latest-run.#{Process.pid}.tmp")
      File.open(temporary, File::WRONLY | File::CREAT | File::TRUNC, 0o600) do |file|
        file.write(JSON.pretty_generate(receipt) + "\n")
        file.flush
        file.fsync
      end
      File.rename(temporary, target)
    ensure
      FileUtils.rm_f(temporary) if defined?(temporary) && temporary && File.exist?(temporary)
    end
  end
end
