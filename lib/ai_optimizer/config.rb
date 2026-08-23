# frozen_string_literal: true

require "fileutils"
require "json"
require "securerandom"

module AIOptimizer
  class Config
    PRODUCT_ID = "ai-env-optimizer"
    LEGACY_PRODUCT_IDS = ["ai-optimizer"].freeze
    APPLICATION_SUPPORT_NAME = "io.github.nyldn.ai-env-optimizer"
    LEGACY_APPLICATION_SUPPORT_NAMES = ["io.github.nyldn.ai-optimizer"].freeze
    DEFAULT_STORAGE_WARNING_BYTES = 10 * 1024 * 1024 * 1024

    attr_reader :data_dir, :path, :manifest_path, :default_workspace_root

    def self.default_data_dir(home = Dir.home)
      support = File.join(home, "Library", "Application Support")
      canonical = File.join(support, APPLICATION_SUPPORT_NAME)
      return canonical if File.exist?(canonical)

      legacy = LEGACY_APPLICATION_SUPPORT_NAMES.map { |name| File.join(support, name) }
                                                .find { |path| File.exist?(path) }
      legacy || canonical
    end

    def initialize(data_dir: nil, default_workspace_root: nil)
      @data_dir = File.expand_path(data_dir || self.class.default_data_dir)
      @path = File.join(@data_dir, "config.json")
      @manifest_path = File.join(@data_dir, "state-manifest.json")
      @default_workspace_root = File.expand_path(default_workspace_root || inferred_workspace_root)
    end

    def defaults
      {
        "schema_version" => 1,
        "workspace_root" => default_workspace_root,
        "schedule" => { "enabled" => false, "hour" => 21, "minute" => 0 },
        "storage" => { "warning_bytes" => DEFAULT_STORAGE_WARNING_BYTES },
        "telemetry" => false
      }
    end

    def storage_warning_bytes(values = nil)
      loaded = values || load
      storage = loaded["storage"]
      candidate = storage.is_a?(Hash) ? storage["warning_bytes"] : nil
      candidate.is_a?(Integer) && candidate.positive? ? candidate : DEFAULT_STORAGE_WARNING_BYTES
    rescue ConfigError, OwnershipError
      DEFAULT_STORAGE_WARNING_BYTES
    end

    def load
      verify_existing_ownership
      return defaults unless File.file?(path)
      raise OwnershipError, "refusing to read symlinked config" if File.symlink?(path)

      parsed = JSON.parse(File.binread(path))
      raise ConfigError, "config root must be an object" unless parsed.is_a?(Hash)

      defaults.merge(parsed)
    rescue JSON::ParserError => error
      raise ConfigError, "invalid config JSON: #{error.message}"
    end

    def save(config)
      raise ConfigError, "config root must be an object" unless config.is_a?(Hash)

      serialized = JSON.pretty_generate(config) + "\n"
      JSON.parse(serialized)
      claim_directory
      atomic_write(path, serialized, 0o600)
      write_manifest
      config
    rescue JSON::GeneratorError, JSON::ParserError => error
      raise ConfigError, "invalid config: #{error.message}"
    end

    def save_json(serialized)
      parsed = JSON.parse(serialized)
      save(parsed)
    rescue JSON::ParserError => error
      raise ConfigError, "invalid config JSON: #{error.message}"
    end

    def atomic_write(target, content, mode)
      assert_contained_target(target)
      temporary = File.join(data_dir, ".#{File.basename(target)}.#{Process.pid}.#{SecureRandom.hex(4)}.tmp")
      File.open(temporary, File::WRONLY | File::CREAT | File::EXCL, mode) do |file|
        file.write(content)
        file.flush
        file.fsync
      end
      File.chmod(mode, temporary)
      File.rename(temporary, target)
    ensure
      FileUtils.rm_f(temporary) if defined?(temporary) && temporary && File.exist?(temporary)
    end

    private

    def inferred_workspace_root
      candidate = File.join(Dir.home, "git")
      Dir.exist?(candidate) ? candidate : Dir.pwd
    end

    def claim_directory
      raise OwnershipError, "data directory must not be a symlink" if File.symlink?(data_dir)

      if File.exist?(data_dir) && !File.directory?(data_dir)
        raise OwnershipError, "AI Environment Optimizer data path is not a directory"
      end
      FileUtils.mkdir_p(data_dir, mode: 0o700)
      File.chmod(0o700, data_dir)
      entries = Dir.children(data_dir)
      if !entries.empty? && !owned_manifest?
        raise OwnershipError, "refusing to claim a nonempty unowned data directory"
      end
      write_manifest unless owned_manifest?
    end

    def assert_contained_target(target)
      expanded = File.expand_path(target)
      prefix = data_dir.end_with?(File::SEPARATOR) ? data_dir : data_dir + File::SEPARATOR
      raise OwnershipError, "write target is outside AI Environment Optimizer data" unless expanded.start_with?(prefix)
      raise OwnershipError, "refusing to replace a symlink" if File.symlink?(expanded)
    end

    def verify_existing_ownership
      return unless Dir.exist?(data_dir)
      return if Dir.children(data_dir).empty?
      return if owned_manifest?

      raise OwnershipError, "AI Environment Optimizer data directory is not product-owned"
    end

    def owned_manifest?
      return false unless File.file?(manifest_path) && !File.symlink?(manifest_path)

      owner = JSON.parse(File.binread(manifest_path)).fetch("owner", nil)
      ([PRODUCT_ID] + LEGACY_PRODUCT_IDS).include?(owner)
    rescue JSON::ParserError
      false
    end

    def write_manifest
      manifest = {
        "schema_version" => 1,
        "owner" => PRODUCT_ID,
        "version" => VERSION,
        "files" => [File.basename(path), File.basename(manifest_path)]
      }
      atomic_write(manifest_path, JSON.pretty_generate(manifest) + "\n", 0o600)
    end
  end
end
