# frozen_string_literal: true

require "rails_helper"

# The cached number the /franchises tiles are cached under (fix pass of spec
# api#487): bumped once the change commits, never reused after the cache
# loses it.
RSpec.describe Franchises::BrowseVersion do
  include ActiveSupport::Testing::TimeHelpers

  around do |example|
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    example.run
  ensure
    Rails.cache = original_cache
  end

  it "changes on each bump" do
    first = described_class.current

    described_class.bump!
    described_class.bump!

    expect(described_class.current).to eq(first + 2)
  end

  it "bumps from a cold cache too" do
    described_class.bump!

    expect(described_class.current).to eq(Rails.cache.read(described_class::KEY))
    expect { described_class.bump! }.to change(described_class, :current).by(1)
  end

  it "waits for the transaction to commit" do
    first = described_class.current

    ApplicationRecord.transaction do
      described_class.bump!
      expect(described_class.current).to eq(first)
    end

    expect(described_class.current).to eq(first + 1)
  end

  it "starts past any version used before the cache lost it" do
    first = described_class.current
    Rails.cache.clear
    travel 1.second

    expect(described_class.current).to be > first
  ensure
    travel_back
  end
end
