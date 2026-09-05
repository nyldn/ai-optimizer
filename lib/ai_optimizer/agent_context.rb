# frozen_string_literal: true

module AIOptimizer
  class AgentContext
    WORKFLOW = [
      "Read the diagnostic evidence before changing configuration or code.",
      "For desktop work, confirm the app mode and execution host; CLI presence or authentication does not prove desktop readiness.",
      "Investigate one prioritized finding at its owning source.",
      "Make the smallest reversible repair only when the user asked for changes.",
      "Re-run agent-context after any approved repair and include focused verification."
    ].freeze

    NEVER = [
      "Do not expose credentials, environment values, MCP endpoints, or workspace contents.",
      "Do not silently install, upgrade, remove, or reconfigure third-party tools.",
      "Do not treat a warning as permission to mutate the host."
    ].freeze

    PRIORITY_ORDER = { "P0" => 0, "P1" => 1, "P2" => 2 }.freeze

    attr_reader :doctor_report, :scan_report, :generated_at, :version

    def initialize(doctor_report:, scan_report:, generated_at: Time.now.utc, version: VERSION)
      @doctor_report = doctor_report
      @scan_report = scan_report
      @generated_at = generated_at.utc
      @version = version
    end

    def to_h
      {
        schema_version: 1,
        product: "ai-env-optimizer",
        compatibility: { legacy_names: ["ai-optimizer"] },
        version: version,
        generated_at: generated_at.iso8601,
        mode: "read_only_advisor",
        overall_status: overall_status,
        agent_contract: {
          diagnostics_are_read_only: true,
          repairs_are_automatic: false,
          workflow: WORKFLOW,
          never: NEVER,
          completion_gate: [
            "Verify the original finding no longer reproduces.",
            "Run the relevant native tool doctor or product test.",
            "Re-run agent-context and report remaining warnings or failures."
          ]
        },
        prioritized_actions: prioritized_actions,
        reports: {
          doctor: doctor_report.to_h,
          scan: scan_report.to_h
        }
      }
    end

    def to_json(*_args)
      JSON.generate(to_h)
    end

    def to_text
      lines = [
        "AI Environment Optimizer agent context #{version}",
        "Mode: read-only advisor",
        "Overall: #{overall_status}",
        "",
        "Agent workflow:"
      ]
      WORKFLOW.each_with_index { |step, index| lines << "#{index + 1}. #{step}" }
      lines << ""
      lines << "Safety boundary:"
      NEVER.each { |rule| lines << "- #{rule}" }
      lines << ""
      lines << "Prioritized actions:"
      if prioritized_actions.empty?
        lines << "- None. Preserve the current state."
      else
        prioritized_actions.each do |action|
          lines << "[#{action.fetch(:priority)}] #{action.fetch(:finding_id)} - #{action.fetch(:message)}"
          remediation = action[:remediation]
          lines << "  Next: #{remediation}" if remediation && !remediation.empty?
        end
      end
      lines.join("\n") + "\n"
    end

    def exit_code(strict: false)
      [doctor_report.exit_code(strict: strict), scan_report.exit_code(strict: strict)].max
    end

    private

    def overall_status
      return "action_required" if prioritized_actions.any? { |action| action.fetch(:priority) == "P0" }
      return "review" unless prioritized_actions.empty?

      "healthy"
    end

    def prioritized_actions
      @prioritized_actions ||= begin
        entries = []
        { "doctor" => doctor_report, "scan" => scan_report }.each do |source, report|
          report.findings.each do |finding|
            priority = priority_for(finding)
            entries << [finding, priority, source] if priority
          end
        end

        entries.group_by { |finding, _priority, _source| finding.id }.map do |_id, matches|
          selected = matches.min_by { |_finding, priority, _source| PRIORITY_ORDER.fetch(priority) }
          finding = selected[0]
          {
            priority: selected[1],
            finding_id: finding.id,
            status: finding.status,
            message: finding.message,
            remediation: finding.remediation,
            required: finding.required,
            affects: finding.affects,
            source_reports: matches.map { |_item, _priority, source| source }.uniq.sort
          }
        end.sort_by { |action| [PRIORITY_ORDER.fetch(action.fetch(:priority)), action.fetch(:finding_id)] }
      end
    end

    def priority_for(finding)
      return "P0" if finding.required && %w[fail unknown].include?(finding.status)
      return "P1" if %w[fail unknown].include?(finding.status)
      return "P2" if finding.status == "warn"

      nil
    end
  end
end
