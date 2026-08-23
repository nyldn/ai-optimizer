# frozen_string_literal: true

require "find"
require "set"

module AIOptimizer
  class StorageScanner
    AGE_BUCKETS = [
      ["0_7_days", 0, 7],
      ["8_30_days", 8, 30],
      ["31_90_days", 31, 90],
      ["over_90_days", 91, Float::INFINITY]
    ].freeze

    attr_reader :sources, :home, :data_dir

    def initialize(sources:, home:, data_dir:, clock: -> { Time.now })
      @sources = Array(sources).freeze
      @home = File.expand_path(home)
      @data_dir = File.expand_path(data_dir)
      @clock = clock
    end

    def scan
      sources.map { |source| measure(source) }.freeze
    end

    private

    def measure(source)
      path = source.resolve(home: home, data_dir: data_dir)
      return empty_measurement(source, "unknown") if File.symlink?(path)
      return empty_measurement(source, "absent") unless File.exist?(path)

      bytes = 0
      file_count = 0
      directory_count = 0
      buckets = empty_buckets
      seen = Set.new

      Find.find(path) do |entry|
        stat = File.lstat(entry)
        next if stat.symlink?

        identity = [stat.dev, stat.ino]
        next if seen.include?(identity)

        seen << identity
        allocated = allocated_bytes(stat)
        bytes += allocated
        buckets[bucket_for(stat)] += allocated
        file_count += 1 if stat.file?
        directory_count += 1 if stat.directory?
      end

      base_measurement(source).merge(
        "status" => "complete",
        "allocated_bytes" => bytes,
        "file_count" => file_count,
        "directory_count" => directory_count,
        "age_buckets" => buckets.freeze
      ).freeze
    rescue SystemCallError, OwnershipError
      empty_measurement(source, "unknown")
    end

    def empty_measurement(source, status)
      base_measurement(source).merge(
        "status" => status,
        "allocated_bytes" => 0,
        "file_count" => 0,
        "directory_count" => 0,
        "age_buckets" => empty_buckets.freeze
      ).freeze
    end

    def base_measurement(source)
      {
        "id" => source.id,
        "provider" => source.provider,
        "classification" => source.classification,
        "cleanup_eligible" => source.cleanup_eligible?
      }
    end

    def empty_buckets
      AGE_BUCKETS.each_with_object({}) { |(name, _minimum, _maximum), result| result[name] = 0 }
    end

    def allocated_bytes(stat)
      blocks = stat.respond_to?(:blocks) ? stat.blocks : nil
      blocks ? blocks * 512 : stat.size
    end

    def bucket_for(stat)
      days = [((@clock.call - stat.mtime) / 86_400).floor, 0].max
      match = AGE_BUCKETS.find { |_name, minimum, maximum| days >= minimum && days <= maximum }
      match.fetch(0)
    end
  end
end
