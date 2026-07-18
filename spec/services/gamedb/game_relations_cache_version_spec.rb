# frozen_string_literal: true

require "rails_helper"

# Behavioral coverage for the shared cache-invalidation counter (#154 review):
# GamesController#relations_data folds this into its cache key to invalidate
# every game's cached relations when a GOTM/NR-GOTM entry or a manual image
# changes -- neither of which touches any single game's own `updated_at`.
RSpec.describe Gamedb::GameRelationsCacheVersion do
  around do |example|
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    example.run
  ensure
    Rails.cache = original_cache
  end

  it "starts at 1 and increments on each bump" do
    expect(described_class.current).to eq(1)

    described_class.bump!
    expect(described_class.current).to eq(2)

    described_class.bump!
    expect(described_class.current).to eq(3)
  end
end
