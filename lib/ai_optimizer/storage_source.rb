# frozen_string_literal: true

module AIOptimizer
  class StorageSource
    CLASSIFICATIONS = %w[regenerable bounded_logs historical active].freeze
    BASES = %i[home application_support data_dir].freeze

    attr_reader :id, :provider, :base, :components, :classification,
                :process_names

    def initialize(id:, provider:, base:, components:, classification:,
                   cleanup_eligible:, process_names: [])
      raise ArgumentError, "invalid source id" unless id.to_s.match?(/\A[a-z0-9_.]+\z/)
      raise ArgumentError, "invalid provider" unless provider.to_s.match?(/\A[a-z0-9-]+\z/)
      raise ArgumentError, "invalid classification" unless CLASSIFICATIONS.include?(classification)
      raise ArgumentError, "invalid base" unless BASES.include?(base)
      raise ArgumentError, "storage source needs components" if components.empty?
      if components.any? { |item| item.to_s.empty? || %w[. ..].include?(item) || item.to_s.include?(File::SEPARATOR) }
        raise OwnershipError, "unsafe storage component"
      end
      if cleanup_eligible && %w[historical active].include?(classification)
        raise ArgumentError, "protected storage cannot be cleanup eligible"
      end

      @id = id.to_s.dup.freeze
      @provider = provider.to_s.dup.freeze
      @base = base
      @components = components.map { |item| item.to_s.dup.freeze }.freeze
      @classification = classification.dup.freeze
      @cleanup_eligible = !!cleanup_eligible
      @process_names = process_names.map { |item| item.to_s.dup.freeze }.freeze
      freeze
    end

    def cleanup_eligible?
      @cleanup_eligible
    end

    def resolve(home:, data_dir:)
      root = case base
             when :home
               File.expand_path(home)
             when :application_support
               File.join(File.expand_path(home), "Library", "Application Support")
             when :data_dir
               File.expand_path(data_dir)
             end
      path = File.expand_path(File.join(root, *components))
      prefix = root.end_with?(File::SEPARATOR) ? root : root + File::SEPARATOR
      raise OwnershipError, "storage source escapes its base" unless path.start_with?(prefix)

      path
    end
  end
end
