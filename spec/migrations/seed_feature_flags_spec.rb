# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20261110130100_seed_feature_flags_live.rb")

# Shipping Feature Flags changes nothing anyone sees: the seed migration sets
# every Feature Live and logs it as "system" (spec #347). The test database is
# loaded from schema.rb, so this runs the migration against it directly.
RSpec.describe SeedFeatureFlagsLive do
  def migrate_up
    ActiveRecord::Migration.suppress_messages { described_class.new.migrate(:up) }
  end

  # The Features that existed when Feature Flags shipped. A Feature
  # registered later (the News Hub, spec #355) is not seeded and so starts
  # in Preview.
  seeded = described_class::KEYS

  it "leaves the 11 Features that existed then Live" do
    migrate_up

    expect(seeded.size).to eq(11)
    expect(Features.states.slice(*seeded)).to eq(seeded.index_with { "live" })
  end

  it "leaves a Feature registered later with no stored state, so it reads as Preview" do
    migrate_up

    expect(Features.keys - seeded).to eq([ "news_hub" ])
    expect(FeatureFlag.where(key: "news_hub")).to be_empty
    expect(Features.state("news_hub")).to eq("preview")
  end

  it "logs each seeded Feature as a change by system" do
    migrate_up

    expect(FeatureFlagChange.pluck(:feature_key, :from_state, :to_state, :changed_by))
      .to match_array(seeded.map { |key| [ key, nil, "live", "system" ] })
  end

  it "leaves a Feature that already has a state, and its log, alone" do
    FeatureFlag.change!("journals", "off", by: "123")

    expect { migrate_up }.to change(FeatureFlagChange, :count).by(10)
    expect(Features.state("journals")).to eq("off")
  end
end
