# frozen_string_literal: true

module AIOptimizer
  class DiagnosticEngine
    def initialize(context, checks)
      @context = context
      @checks = checks
    end

    def run
      findings = @checks.each_with_object([]) do |check_class, all|
        check = check_class.new(@context)
        begin
          all.concat(check.call)
        rescue StandardError
          all << Finding.new(
            id: "checks.#{underscore(check_class.name.split("::").last)}.unknown",
            category: "internal",
            status: "unknown",
            message: "A diagnostic check could not complete",
            detail: "The failure was contained; sensitive command output was discarded.",
            remediation: "Run the native tool doctor, then retry AI Environment Optimizer.",
            required: check.required?,
            affects: ["ai-env-optimizer"]
          )
        end
      end
      Report.new(findings)
    end

    private

    def underscore(value)
      value.gsub(/([a-z0-9])([A-Z])/, '\1_\2').downcase
    end
  end

  class Doctor
    CHECKS = [SystemCheck, ToolsCheck, DesktopCheck, MCPCheck, SkillsCheck, ProductCheck].freeze

    def initialize(context)
      @context = context
    end

    def run
      DiagnosticEngine.new(@context, CHECKS).run
    end
  end

  class Scanner
    CHECKS = (Doctor::CHECKS + [WorkspaceCheck]).freeze

    def initialize(context)
      @context = context
    end

    def run
      DiagnosticEngine.new(@context, CHECKS).run
    end
  end
end
