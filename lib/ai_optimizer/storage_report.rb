# frozen_string_literal: true

require "json"
require "time"

module AIOptimizer
  class StorageReport
    DEFAULT_WARNING_BYTES = 10 * 1024 * 1024 * 1024
    PUBLIC_SOURCE_KEYS = %w[
      id provider classification cleanup_eligible status allocated_bytes
      file_count directory_count age_buckets
    ].freeze

    attr_reader :measurements, :generated_at, :version, :warning_bytes

    def initialize(measurements, generated_at: Time.now.utc, version: VERSION,
                   warning_bytes: DEFAULT_WARNING_BYTES)
      raise ArgumentError, "warning bytes must be positive" unless warning_bytes.is_a?(Integer) && warning_bytes.positive?

      @measurements = Array(measurements).map { |item| public_measurement(item) }
                                         .sort_by { |item| item.fetch("id") }
                                         .freeze
      @generated_at = generated_at.utc
      @version = version
      @warning_bytes = warning_bytes
    end

    def summary
      complete = measurements.select { |item| item.fetch("status") == "complete" }
      {
        "allocated_bytes" => complete.sum { |item| item.fetch("allocated_bytes") },
        "reclaimable_bytes" => complete.select { |item| item.fetch("cleanup_eligible") }
                                         .sum { |item| item.fetch("allocated_bytes") },
        "protected_bytes" => complete.reject { |item| item.fetch("cleanup_eligible") }
                                      .sum { |item| item.fetch("allocated_bytes") },
        "unknown_sources" => measurements.count { |item| item.fetch("status") == "unknown" }
      }
    end

    def to_h
      {
        "schema_version" => 1,
        "product" => "ai-env-optimizer",
        "compatibility" => { "legacy_names" => ["ai-optimizer"] },
        "version" => version,
        "generated_at" => generated_at.iso8601,
        "summary" => summary,
        "sources" => measurements
      }
    end

    def to_json(*_args)
      JSON.generate(to_h)
    end

    def to_text
      totals = summary
      lines = [
        "AI Environment Optimizer storage #{version}",
        "",
        "Allocated: #{format_bytes(totals.fetch("allocated_bytes"))}",
        "Potentially reclaimable: #{format_bytes(totals.fetch("reclaimable_bytes"))}",
        "Protected: #{format_bytes(totals.fetch("protected_bytes"))}",
        ""
      ]
      measurements.each do |item|
        lines << "[#{label(item)}] #{item.fetch("id")} - #{format_bytes(item.fetch("allocated_bytes"))} (#{item.fetch("classification")})"
      end
      lines.join("\n") + "\n"
    end

    def exit_code(strict: false)
      return 1 if summary.fetch("unknown_sources").positive?
      return 1 if strict && summary.fetch("allocated_bytes") >= warning_bytes

      0
    end

    private

    def public_measurement(item)
      PUBLIC_SOURCE_KEYS.each_with_object({}) do |key, result|
        result[key] = item.fetch(key)
      end.freeze
    end

    def label(item)
      return "ABSENT" if item.fetch("status") == "absent"
      return "UNKNOWN" if item.fetch("status") == "unknown"
      return "RECLAIMABLE" if item.fetch("cleanup_eligible")

      "PROTECTED"
    end

    def format_bytes(bytes)
      units = %w[B KiB MiB GiB TiB]
      value = bytes.to_f
      unit = units.shift
      while value >= 1024 && !units.empty?
        value /= 1024
        unit = units.shift
      end
      value < 10 && unit != "B" ? format("%.1f %s", value, unit) : format("%.0f %s", value, unit)
    end
  end
end
