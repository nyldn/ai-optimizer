# frozen_string_literal: true

require "json"
require "time"

module AIOptimizer
  class Report
    attr_reader :findings, :generated_at, :version

    def initialize(findings, generated_at: Time.now.utc, version: VERSION)
      @findings = Array(findings).sort_by { |finding| [finding.category, finding.id] }.freeze
      duplicate = @findings.group_by(&:id).find { |_id, matches| matches.length > 1 }
      raise ArgumentError, "duplicate finding id: #{duplicate.first}" if duplicate

      @generated_at = generated_at.utc
      @version = version
    end

    def summary
      Finding::STATUSES.each_with_object({}) do |status, counts|
        counts[status] = findings.count { |finding| finding.status == status }
      end
    end

    def to_h
      {
        schema_version: 1,
        product: "ai-env-optimizer",
        compatibility: { legacy_names: ["ai-optimizer"] },
        version: version,
        generated_at: generated_at.iso8601,
        summary: summary,
        findings: findings.map(&:to_h)
      }
    end

    def to_json(*_args)
      JSON.generate(to_h)
    end

    def to_text(color: default_color?)
      lines = ["AI Environment Optimizer #{version}", ""]
      findings.each do |finding|
        label = finding.status.upcase
        label = colorize(label, finding.status) if color
        lines << "[#{label}] #{finding.id} - #{finding.message}"
        lines << "  #{finding.detail}" if finding.detail && !finding.detail.to_s.empty?
        lines << "  Next: #{finding.remediation}" if finding.remediation && !finding.remediation.to_s.empty?
      end
      lines << ""
      lines << summary_text
      lines.join("\n") + "\n"
    end

    def exit_code(strict: false)
      return 1 if findings.any? { |finding| finding.required && %w[fail unknown].include?(finding.status) }
      return 1 if strict && findings.any? { |finding| finding.status == "warn" }

      0
    end

    private

    def summary_text
      counts = summary
      parts = []
      parts << pluralize(counts["pass"], "passed")
      parts << pluralize(counts["warn"], "warning")
      parts << pluralize(counts["fail"], "failure")
      parts << pluralize(counts["unknown"], "unknown")
      parts.reject { |part| part.start_with?("0 ") }.join(", ")
    end

    def pluralize(count, noun)
      return "#{count} #{noun}" if count == 1
      return "#{count} warnings" if noun == "warning"
      return "#{count} failures" if noun == "failure"

      "#{count} #{noun}"
    end

    def default_color?
      ENV["NO_COLOR"].nil? && $stdout.tty?
    end

    def colorize(text, status)
      code = { "pass" => 32, "warn" => 33, "fail" => 31, "unknown" => 35, "info" => 36, "skip" => 90 }.fetch(status)
      "\e[#{code}m#{text}\e[0m"
    end
  end
end
