# frozen_string_literal: true

require "fileutils"
require "json"
require "securerandom"

module AIOptimizer
  class Config
    APPLICATION_SUPPORT_NAME = "io.github.nyldn.ai-optimizer"

    attr_reader :data_dir, :path, :manifest_path, :default_workspace_root

    def self.default_data_dir(home = Dir.home)
      File.join(home, "Library", "Application Support", APPLICATION_SUPPORT_NAME)
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
        "telemetry" => false
      }
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
        raise OwnershipError, "AI Optimizer data path is not a directory"
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
      raise OwnershipError, "write target is outside AI Optimizer data" unless expanded.start_with?(prefix)
      raise OwnershipError, "refusing to replace a symlink" if File.symlink?(expanded)
    end

    def verify_existing_ownership
      return unless Dir.exist?(data_dir)
      return if Dir.children(data_dir).empty?
      return if owned_manifest?

      raise OwnershipError, "AI Optimizer data directory is not product-owned"
    end

    def owned_manifest?
      return false unless File.file?(manifest_path) && !File.symlink?(manifest_path)

      JSON.parse(File.binread(manifest_path)).fetch("owner", nil) == "ai-optimizer"
    rescue JSON::ParserError
      false
    end

    def write_manifest
      manifest = {
        "schema_version" => 1,
        "owner" => "ai-optimizer",
        "version" => VERSION,
        "files" => [File.basename(path), File.basename(manifest_path)]
      }
      atomic_write(manifest_path, JSON.pretty_generate(manifest) + "\n", 0o600)
    end
  end
end
