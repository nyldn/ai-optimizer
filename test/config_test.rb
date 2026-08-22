# frozen_string_literal: true

require_relative "test_helper"

class ConfigTest < Minitest::Test
  def test_round_trip_uses_private_permissions_and_preserves_unknown_keys
    in_tmpdir do |dir|
      config = AIOptimizer::Config.new(data_dir: File.join(dir, "data"), default_workspace_root: dir)
      config.save(config.defaults.merge("future_key" => { "enabled" => true }))

      assert_equal true, config.load.fetch("future_key").fetch("enabled")
      assert_equal 0o600, File.stat(config.path).mode & 0o777
      assert_equal "ai-optimizer", JSON.parse(File.read(config.manifest_path)).fetch("owner")
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
