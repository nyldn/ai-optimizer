# frozen_string_literal: true

module AIOptimizer
  class Finding
    STATUSES = %w[pass warn fail info skip unknown].freeze

    attr_reader :id, :category, :status, :message, :detail, :remediation,
                :required, :affects, :links

    def initialize(id:, category:, status:, message:, detail: nil,
                   remediation: nil, required: false, affects: [], links: [])
      raise ArgumentError, "finding id must not be empty" if id.to_s.empty?
      raise ArgumentError, "finding category must not be empty" if category.to_s.empty?
      raise ArgumentError, "invalid finding status: #{status}" unless STATUSES.include?(status.to_s)
      raise ArgumentError, "finding message must not be empty" if message.to_s.empty?

      @id = id.to_s
      @category = category.to_s
      @status = status.to_s
      @message = message.to_s
      @detail = detail
      @remediation = remediation
      @required = !!required
      @affects = Array(affects).map(&:to_s).freeze
      @links = Array(links).map(&:to_s).freeze
      freeze
    end

    def to_h
      {
        id: id,
        category: category,
        status: status,
        message: message,
        detail: detail,
        remediation: remediation,
        required: required,
        affects: affects,
        links: links
      }
    end
  end
end
