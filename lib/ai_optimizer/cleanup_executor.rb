# frozen_string_literal: true

require "fileutils"
require "json"
require "time"

module AIOptimizer
  class CleanupExecutor
    attr_reader :planner, :config, :trash_root

    def initialize(planner:, config:, trash_root:, clock: -> { Time.now },
                   process_guard: nil, device_reader: nil, mover: nil)
      @planner = planner
      @config = config
      @trash_root = File.expand_path(trash_root)
      @clock = clock
      @process_guard = process_guard || method(:provider_running?)
      @device_reader = device_reader || ->(path) { File.stat(path).dev }
      @mover = mover || ->(source, destination) { File.rename(source, destination) }
    end

    def apply(token:, older_than_days:, min_size_mb:)
      plan = planner.preview(
        older_than_days: older_than_days,
        min_size_mb: min_size_mb
      )
      unless secure_equal?(plan.token, token)
        raise UsageError, "cleanup preview expired; run --dry-run again"
      end
      raise UsageError, "cleanup preview has no eligible files" if plan.candidates.empty?

      validate_trash_root
      process_names = plan.candidates.flat_map { |candidate| candidate.source.process_names }.uniq.sort
      if @process_guard.call(process_names)
        raise InternalError, "close the affected AI application before cleanup"
      end
      validate_devices(plan)

      destination = File.join(trash_root, destination_basename(token))
      if File.exist?(destination) || File.symlink?(destination)
        raise OwnershipError, "cleanup Trash destination already exists"
      end

      claim_product_state
      Dir.mkdir(destination, 0o700)
      File.chmod(0o700, destination)
      move_plan(plan, token, destination)
    end

    private

    def secure_equal?(expected, supplied)
      left = expected.to_s.b
      right = supplied.to_s.b
      return false unless left.bytesize == right.bytesize

      difference = 0
      left.bytes.zip(right.bytes) { |a, b| difference |= a ^ b }
      difference.zero?
    end

    def validate_trash_root
      raise OwnershipError, "Trash root must not be a symlink" if File.symlink?(trash_root)
      unless File.directory?(trash_root)
        raise OwnershipError, "Trash root must be an existing directory"
      end
    end

    def validate_devices(plan)
      trash_device = @device_reader.call(trash_root)
      plan.candidates.each do |candidate|
        candidate_device = @device_reader.call(candidate.path)
        unless candidate_device == trash_device
          raise OwnershipError, "cleanup cannot cross filesystems"
        end
      end
    rescue SystemCallError
      raise OwnershipError, "cleanup filesystem could not be verified"
    end

    def destination_basename(token)
      "ai-env-optimizer-#{@clock.call.utc.strftime("%Y%m%dT%H%M%SZ")}-#{token[0, 12]}"
    end

    def claim_product_state
      config.save(config.load)
    end

    def move_plan(plan, token, destination)
      moved_count = 0
      moved_bytes = 0
      moved_sources = []

      begin
        plan.candidates.each do |candidate|
          validate_candidate(candidate)
          target = candidate_destination(candidate, destination)
          parent = File.dirname(target)
          FileUtils.mkdir_p(parent, mode: 0o700)
          raise OwnershipError, "cleanup destination must not be a symlink" if File.symlink?(target)

          @mover.call(candidate.path, target)
          moved_count += 1
          moved_bytes += candidate.allocated_bytes
          moved_sources << candidate.source.id
        end
      rescue StandardError
        status = moved_count.positive? ? "partial" : "failed"
        write_receipt(
          receipt_for(plan, token, destination, status, moved_count, moved_bytes, moved_sources)
        )
        raise InternalError, "cleanup move failed after #{moved_count} files"
      end

      receipt = receipt_for(
        plan, token, destination, "moved_to_trash", moved_count, moved_bytes, moved_sources
      )
      write_receipt(receipt)
      receipt.merge("trash_path_for_test" => destination)
    end

    def validate_candidate(candidate)
      stat = File.lstat(candidate.path)
      raise OwnershipError, "cleanup candidate became a symlink" if stat.symlink?
      raise UsageError, "cleanup preview expired; run --dry-run again" unless stat.file?

      current = [
        candidate.source.id,
        candidate.relative_path,
        stat.dev,
        stat.ino,
        stat.mode,
        stat.size,
        stat.respond_to?(:blocks) ? stat.blocks : nil,
        (stat.mtime.to_f * 1_000_000).to_i
      ]
      unless current == candidate.identity_row
        raise UsageError, "cleanup preview expired; run --dry-run again"
      end
    rescue SystemCallError
      raise UsageError, "cleanup preview expired; run --dry-run again"
    end

    def candidate_destination(candidate, destination)
      target = File.expand_path(
        File.join(destination, candidate.source.id, candidate.relative_path)
      )
      prefix = destination.end_with?(File::SEPARATOR) ? destination : destination + File::SEPARATOR
      raise OwnershipError, "cleanup destination escapes Trash folder" unless target.start_with?(prefix)

      target
    end

    def receipt_for(plan, token, destination, status, moved_count, moved_bytes, moved_sources)
      {
        "schema_version" => 1,
        "product" => "ai-env-optimizer",
        "compatibility" => { "legacy_names" => ["ai-optimizer"] },
        "status" => status,
        "generated_at" => @clock.call.utc.iso8601,
        "token" => token,
        "trash_folder" => File.basename(destination),
        "moved_files" => moved_count,
        "moved_bytes" => moved_bytes,
        "sources" => moved_sources.uniq.sort,
        "requested" => {
          "older_than_days" => plan.older_than_days,
          "min_size_mb" => plan.min_size_mb
        }
      }
    end

    def write_receipt(receipt)
      reports_dir = File.join(config.data_dir, "reports")
      raise OwnershipError, "reports directory must not be a symlink" if File.symlink?(reports_dir)
      if File.exist?(reports_dir) && !File.directory?(reports_dir)
        raise OwnershipError, "reports path is not a directory"
      end

      Dir.mkdir(reports_dir, 0o700) unless File.directory?(reports_dir)
      File.chmod(0o700, reports_dir)
      target = File.join(reports_dir, "latest-cleanup.json")
      config.atomic_write(target, JSON.pretty_generate(receipt) + "\n", 0o600)
    end

    def provider_running?(names)
      runner = CommandRunner.new
      names.any? do |name|
        runner.run(["/usr/bin/pgrep", "-x", name], timeout: 3).success?
      end
    end
  end
end
