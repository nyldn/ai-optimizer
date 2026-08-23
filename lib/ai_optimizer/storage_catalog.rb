# frozen_string_literal: true

module AIOptimizer
  class StorageCatalog
    DEFINITIONS = [
      ["claude.projects", "claude", :home, [".claude", "projects"], "historical", false, []],
      ["claude.plugin_cache", "claude", :home, [".claude", "plugins", "cache"], "active", false, []],
      ["claude.marketplaces", "claude", :home, [".claude", "plugins", "marketplaces"], "active", false, []],
      ["claude.app_cache", "claude", :application_support, ["Claude", "Cache"], "regenerable", true, ["Claude"]],
      ["claude.code_cache", "claude", :application_support, ["Claude", "Code Cache"], "regenerable", true, ["Claude"]],
      ["claude.gpu_cache", "claude", :application_support, ["Claude", "GPUCache"], "regenerable", true, ["Claude"]],
      ["claude.local_sessions", "claude", :application_support, ["Claude", "local-agent-mode-sessions"], "historical", false, []],
      ["claude.vm_bundles", "claude", :application_support, ["Claude", "vm_bundles"], "active", false, []],
      ["codex.sessions", "codex", :home, [".codex", "sessions"], "historical", false, []],
      ["codex.archived_sessions", "codex", :home, [".codex", "archived_sessions"], "historical", false, []],
      ["codex.plugins", "codex", :home, [".codex", "plugins"], "active", false, []],
      ["codex.worktrees", "codex", :home, [".codex", "worktrees"], "active", false, []],
      ["codex.cache", "codex", :home, [".codex", "cache"], "regenerable", true, ["Codex"]],
      ["claude_mem.index", "claude-mem", :home, [".claude-mem", "chroma"], "historical", false, []],
      ["claude_mem.database", "claude-mem", :home, [".claude-mem", "claude-mem.db"], "historical", false, []],
      ["claude_mem.logs", "claude-mem", :home, [".claude-mem", "logs"], "bounded_logs", false, []],
      ["product.logs", "ai-env-optimizer", :data_dir, ["logs"], "bounded_logs", true, []]
    ].freeze

    attr_reader :home, :data_dir, :sources

    def initialize(home:, data_dir:)
      @home = File.expand_path(home)
      @data_dir = File.expand_path(data_dir)
      @sources = DEFINITIONS.map do |id, provider, base, components, classification, eligible, processes|
        StorageSource.new(
          id: id,
          provider: provider,
          base: base,
          components: components,
          classification: classification,
          cleanup_eligible: eligible,
          process_names: processes
        )
      end.freeze
      validate_unique_ids
      validate_non_overlapping_paths
    end

    private

    def validate_unique_ids
      ids = sources.map(&:id)
      raise InternalError, "duplicate storage source id" unless ids.uniq.length == ids.length
    end

    def validate_non_overlapping_paths
      paths = sources.map { |source| source.resolve(home: home, data_dir: data_dir) }
      paths.combination(2) do |left, right|
        left_prefix = left.end_with?(File::SEPARATOR) ? left : left + File::SEPARATOR
        right_prefix = right.end_with?(File::SEPARATOR) ? right : right + File::SEPARATOR
        if left == right || left.start_with?(right_prefix) || right.start_with?(left_prefix)
          raise InternalError, "overlapping storage sources"
        end
      end
    end
  end
end
