# frozen_string_literal: true

require_relative "test_helper"

class ConfigTest < Minitest::Test
  def test_defaults_include_report_only_storage_warning_threshold
    in_tmpdir do |dir|
      config = AIOptimizer::Config.new(data_dir: File.join(dir, "data"), default_workspace_root: dir)

      assert_equal 10 * 1024 * 1024 * 1024,
                   config.defaults.fetch("storage").fetch("warning_bytes")
    end
  end

  def test_invalid_storage_warning_threshold_falls_back_to_default
    in_tmpdir do |dir|
      config = AIOptimizer::Config.new(data_dir: File.join(dir, "data"), default_workspace_root: dir)

      assert_equal 10 * 1024 * 1024 * 1024,
                   config.storage_warning_bytes("storage" => { "warning_bytes" => -1 })
      assert_equal 10 * 1024 * 1024 * 1024,
                   config.storage_warning_bytes("storage" => { "warning_bytes" => "large" })
    end
  end

  def test_default_data_dir_prefers_canonical_path_for_new_users
    in_tmpdir do |home|
      expected = File.join(home, "Library", "Application Support", "io.github.nyldn.ai-env-optimizer")

      assert_equal expected, AIOptimizer::Config.default_data_dir(home)
    end
  end

  def test_default_data_dir_preserves_an_existing_legacy_install
    in_tmpdir do |home|
      legacy = File.join(home, "Library", "Application Support", "io.github.nyldn.ai-optimizer")
      FileUtils.mkdir_p(legacy)

      assert_equal legacy, AIOptimizer::Config.default_data_dir(home)
    end
  end

  def test_round_trip_uses_private_permissions_and_preserves_unknown_keys
    in_tmpdir do |dir|
      config = AIOptimizer::Config.new(data_dir: File.join(dir, "data"), default_workspace_root: dir)
      config.save(config.defaults.merge("future_key" => { "enabled" => true }))

      assert_equal true, config.load.fetch("future_key").fetch("enabled")
      assert_equal 0o600, File.stat(config.path).mode & 0o777
      assert_equal "ai-env-optimizer", JSON.parse(File.read(config.manifest_path)).fetch("owner")
    end
  end

  def test_existing_legacy_manifest_is_accepted_and_upgraded_on_save
    in_tmpdir do |dir|
      data_dir = File.join(dir, "data")
      FileUtils.mkdir_p(data_dir)
      File.write(
        File.join(data_dir, "state-manifest.json"),
        JSON.generate("schema_version" => 1, "owner" => "ai-optimizer", "version" => "0.1.8")
      )
      config = AIOptimizer::Config.new(data_dir: data_dir, default_workspace_root: dir)

      config.save(config.defaults)

      assert_equal "ai-env-optimizer", JSON.parse(File.read(config.manifest_path)).fetch("owner")
    end
  end

  def test_invalid_json_never_replaces_last_valid_config
    in_tmpdir do |dir|
      config = AIOptimizer::Config.new(data_dir: File.join(dir, "data"), default_workspace_root: dir)
      config.save(config.defaults)
      original = File.binread(config.path)

      assert_raises(AIOptimizer::ConfigError) { config.save_json("{not-json") }
      assert_equal original, File.binread(config.path)
    end
  end

  def test_refuses_symlinked_config_target
    in_tmpdir do |dir|
      data_dir = File.join(dir, "data")
      FileUtils.mkdir_p(data_dir)
      target = File.join(dir, "outside.json")
      File.write(target, "{}")
      File.symlink(target, File.join(data_dir, "config.json"))
      config = AIOptimizer::Config.new(data_dir: data_dir, default_workspace_root: dir)

      assert_raises(AIOptimizer::OwnershipError) { config.save(config.defaults) }
      assert_equal "{}", File.read(target)
    end
  end

  def test_refuses_to_claim_nonempty_unowned_data_directory
    in_tmpdir do |dir|
      data_dir = File.join(dir, "data")
      FileUtils.mkdir_p(File.join(data_dir, "backups"))
      protected_file = File.join(data_dir, "backups", "existing.bak")
      File.write(protected_file, "keep me")
      config = AIOptimizer::Config.new(data_dir: data_dir, default_workspace_root: dir)

      assert_raises(AIOptimizer::OwnershipError) { config.save(config.defaults) }
      assert_equal "keep me", File.read(protected_file)
      refute File.exist?(config.manifest_path)
    end
  end
end
