# frozen_string_literal: true

require_relative "test_helper"

class StorageSourceTest < Minitest::Test
  def test_resolves_only_below_the_declared_base
    in_tmpdir do |home|
      data_dir = File.join(home, "data")
      source = AIOptimizer::StorageSource.new(
        id: "claude.projects", provider: "claude", base: :home,
        components: [".claude", "projects"], classification: "historical",
        cleanup_eligible: false
      )

      assert_equal File.join(home, ".claude", "projects"),
                   source.resolve(home: home, data_dir: data_dir)
      assert source.frozen?
      assert source.components.frozen?
    end
  end

  def test_refuses_parent_traversal_and_invalid_identifiers
    assert_raises(AIOptimizer::OwnershipError) do
      AIOptimizer::StorageSource.new(
        id: "bad.source", provider: "test", base: :home,
        components: ["..", "outside"], classification: "regenerable",
        cleanup_eligible: true
      )
    end
    assert_raises(ArgumentError) do
      AIOptimizer::StorageSource.new(
        id: "BAD PATH", provider: "test", base: :home,
        components: ["cache"], classification: "regenerable",
        cleanup_eligible: true
      )
    end
  end

  def test_protected_sources_cannot_be_cleanup_eligible
    %w[historical active].each do |classification|
      assert_raises(ArgumentError) do
        AIOptimizer::StorageSource.new(
          id: "test.#{classification}", provider: "test", base: :home,
          components: [classification], classification: classification,
          cleanup_eligible: true
        )
      end
    end
  end

  def test_catalog_has_unique_non_overlapping_paths_and_protects_history
    in_tmpdir do |home|
      catalog = AIOptimizer::StorageCatalog.new(
        home: home,
        data_dir: File.join(home, "Library", "Application Support", "io.github.nyldn.ai-env-optimizer")
      )
      sources = catalog.sources
      ids = sources.map(&:id)
      resolved = sources.map { |source| source.resolve(home: home, data_dir: catalog.data_dir) }

      assert_equal ids.uniq.sort, ids.sort
      assert_equal resolved.uniq.sort, resolved.sort
      resolved.combination(2) do |left, right|
        refute left.start_with?(right + File::SEPARATOR), "#{left} nested below #{right}"
        refute right.start_with?(left + File::SEPARATOR), "#{right} nested below #{left}"
      end
      protected_sources = sources.select do |source|
        %w[historical active].include?(source.classification)
      end
      refute_empty protected_sources
      assert protected_sources.none?(&:cleanup_eligible?)
      assert sources.any? { |source| source.id == "product.logs" && source.cleanup_eligible? }
    end
  end
end
