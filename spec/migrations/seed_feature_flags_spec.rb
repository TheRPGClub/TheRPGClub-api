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

  it "leaves all 11 Features Live" do
    migrate_up

    expect(Features.states).to eq(Features.keys.index_with { "live" })
    expect(Features.keys.size).to eq(11)
  end

  it "logs each seeded Feature as a change by system" do
    migrate_up

    expect(FeatureFlagChange.pluck(:feature_key, :from_state, :to_state, :changed_by))
      .to match_array(Features.keys.map { |key| [ key, nil, "live", "system" ] })
  end

  it "leaves a Feature that already has a state, and its log, alone" do
    FeatureFlag.change!("journals", "off", by: "123")

    expect { migrate_up }.to change(FeatureFlagChange, :count).by(10)
    expect(Features.state("journals")).to eq("off")
  end
end
