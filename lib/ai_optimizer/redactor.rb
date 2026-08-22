# frozen_string_literal: true

module AIOptimizer
  module Redactor
    MAX_DETAIL_CHARACTERS = 2_000

    module_function

    def scrub(value, home: nil)
      return nil if value.nil?

      text = value.to_s.encode("UTF-8", invalid: :replace, undef: :replace, replace: "?")
      text = text.gsub(home, "~") if home && !home.empty?
      text = text.gsub(%r{https?://[^\s]+}i, "[endpoint redacted]")
      text = text.gsub(/\bBearer\s+[^\s]+/i, "Bearer [redacted]")
      text = text.gsub(/\b(api[_-]?key|token|secret|password)\s*[:=]\s*[^\s,;]+/i, '\\1=[redacted]')
      text = text.gsub(/\b(?:sk|pk|ghp|github_pat|xox[baprs])[-_][A-Za-z0-9_-]{12,}\b/i, "[redacted]")
      text.length > MAX_DETAIL_CHARACTERS ? text[0, MAX_DETAIL_CHARACTERS] : text
    end
  end
end
