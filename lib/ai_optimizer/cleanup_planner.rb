# frozen_string_literal: true

require "digest"
require "find"
require "json"
require "set"

module AIOptimizer
  StorageCandidate = Struct.new(
    :source, :path, :relative_path, :allocated_bytes, :identity_row,
    keyword_init: true
  )

  class CleanupPlan
    attr_reader :candidates, :token, :older_than_days, :min_size_mb

    def initialize(candidates:, token:, older_than_days:, min_size_mb:)
      @candidates = candidates.freeze
      @token = token.freeze
      @older_than_days = older_than_days
      @min_size_mb = min_size_mb
      freeze
    end

    def to_h
      grouped = candidates.group_by { |candidate| candidate.source.id }
      sources = grouped.keys.sort.map do |id|
        matches = grouped.fetch(id)
        {
          "id" => id,
          "cleanup_eligible" => true,
          "candidate_files" => matches.length,
          "allocated_bytes" => matches.sum(&:allocated_bytes)
        }
      end
      {
        "schema_version" => 1,
        "product" => "ai-env-optimizer",
        "compatibility" => { "legacy_names" => ["ai-optimizer"] },
        "mode" => "dry_run",
        "older_than_days" => older_than_days,
        "min_size_mb" => min_size_mb,
        "summary" => {
          "candidate_files" => candidates.length,
          "allocated_bytes" => candidates.sum(&:allocated_bytes)
        },
        "sources" => sources,
        "token" => token
      }
    end
  end

  class CleanupPlanner
    DEFAULT_OLDER_THAN_DAYS = 30
    DEFAULT_MIN_SIZE_MB = 100

    attr_reader :sources, :home, :data_dir

    def initialize(sources:, home:, data_dir:, clock: -> { Time.now })
      @sources = Array(sources).freeze
      @home = File.expand_path(home)
      @data_dir = File.expand_path(data_dir)
      @clock = clock
    end

    def preview(older_than_days: DEFAULT_OLDER_THAN_DAYS,
                min_size_mb: DEFAULT_MIN_SIZE_MB)
      days = validated_integer(older_than_days, 1..3650, "older-than days")
      megabytes = validated_integer(min_size_mb, 1..Float::INFINITY, "minimum size")
      cutoff = @clock.call - (days * 86_400)
      candidates = sources.select(&:cleanup_eligible?).flat_map do |source|
        source_candidates(source, cutoff, megabytes * 1024 * 1024)
      end.sort_by { |candidate| [candidate.source.id, candidate.relative_path] }
      token_rows = [["options", days, megabytes]] + candidates.map(&:identity_row)
      token = Digest::SHA256.hexdigest(JSON.generate(token_rows))
      CleanupPlan.new(
        candidates: candidates,
        token: token,
        older_than_days: days,
        min_size_mb: megabytes
      )
    end

    private

    def validated_integer(value, range, label)
      parsed = Integer(value)
      raise UsageError, "#{label} is out of range" unless range.cover?(parsed)

      parsed
    rescue ArgumentError, TypeError
      raise UsageError, "#{label} must be an integer"
    end

    def source_candidates(source, cutoff, minimum_bytes)
      if source.symlinked_component?(home: home, data_dir: data_dir)
        raise OwnershipError, "cleanup source has a symlinked ancestor"
      end

      root = source.resolve(home: home, data_dir: data_dir)
      return [] unless File.exist?(root)

      matches = []
      seen = Set.new
      Find.find(root) do |entry|
        stat = File.lstat(entry)
        raise OwnershipError, "cleanup source contains a symlink" if stat.symlink?
        next unless stat.file? && stat.mtime < cutoff
        next unless stat.nlink == 1

        identity = [stat.dev, stat.ino]
        next if seen.include?(identity)

        seen << identity
        relative = entry == root ? File.basename(entry) : entry[(root.length + 1)..-1]
        allocated = allocated_bytes(stat)
        matches << StorageCandidate.new(
          source: source,
          path: entry,
          relative_path: relative,
          allocated_bytes: allocated,
          identity_row: [
            source.id, relative, stat.dev, stat.ino, stat.mode, stat.size,
            stat.respond_to?(:blocks) ? stat.blocks : nil, stat.nlink,
            (stat.mtime.to_f * 1_000_000).to_i
          ]
        ).freeze
      end
      matches.sum(&:allocated_bytes) >= minimum_bytes ? matches : []
    rescue SystemCallError
      raise OwnershipError, "cleanup source could not be inspected safely"
    end

    def allocated_bytes(stat)
      blocks = stat.respond_to?(:blocks) ? stat.blocks : nil
      blocks ? blocks * 512 : stat.size
    end
  end
end
