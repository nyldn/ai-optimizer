# frozen_string_literal: true

module AIOptimizer
  class Error < StandardError; end
  class ConfigError < Error; end
  class OwnershipError < Error; end
  class UsageError < Error; end
  class InternalError < Error; end
end
