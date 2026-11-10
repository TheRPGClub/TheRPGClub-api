# frozen_string_literal: true

require "rails_helper"

# Changing a Feature Flag stores its state and appends to the change log
# (spec #347). Read back through Features.state, which is what every caller
# uses.
RSpec.describe FeatureFlag do
  describe ".change!" do
    it "stores the new state and logs who changed it, from and to which state, and why" do
      described_class.change!("journals", "live", by: FeatureFlag::SYSTEM)

      described_class.change!("journals", "off", by: "123456789012345678", reason: "Journal sync broken, pausing")

      expect(Features.state("journals")).to eq("off")
      expect(FeatureFlagChange.where(feature_key: "journals").order(:id).map do |change|
        change.slice(:from_state, :to_state, :changed_by, :reason).symbolize_keys
      end).to eq([
        { from_state: nil, to_state: "live", changed_by: "system", reason: nil },
        { from_state: "live", to_state: "off", changed_by: "123456789012345678", reason: "Journal sync broken, pausing" }
      ])
      expect(FeatureFlagChange.last.created_at).to be_within(1.minute).of(Time.current)
    end

    it "changes and logs nothing when the Feature already has that state" do
      described_class.change!("reviews", "live", by: "system")

      expect { described_class.change!("reviews", "live", by: "1") }.not_to change(FeatureFlagChange, :count)
    end

    it "rejects a key that is not a registered Feature" do
      expect { described_class.change!("dashboard", "off", by: "system") }.to raise_error(KeyError)
    end

    it "rejects a state other than Off, Preview or Live" do
      expect { described_class.change!("reviews", "enabled", by: "system") }
        .to raise_error(ActiveRecord::RecordInvalid)
      expect(Features.state("reviews")).to eq("preview")
    end
  end

  describe "the change log" do
    it "is append-only" do
      described_class.change!("reviews", "live", by: "system")
      change = FeatureFlagChange.last

      expect { change.update!(reason: "rewritten") }.to raise_error(ActiveRecord::ReadOnlyRecord)
      expect { change.destroy! }.to raise_error(ActiveRecord::ReadOnlyRecord)
    end
  end

  it "reads a registered Feature with no stored state as Preview" do
    expect(Features.state("suggestions")).to eq("preview")
    expect(Features.states.values.uniq).to eq([ "preview" ])
  end
end
