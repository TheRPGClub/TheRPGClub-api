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

    it "returns the change it logged" do
      described_class.change!("journals", "live", by: FeatureFlag::SYSTEM)

      change = described_class.change!("journals", "off", by: "123", reason: "Paused")

      expect(change).to eq(FeatureFlagChange.where(feature_key: "journals").order(:id).last)
      expect(change).to have_attributes(from_state: "live", to_state: "off", changed_by: "123", reason: "Paused")
    end

    it "changes and logs nothing, returning nil, when the Feature already has that state" do
      described_class.change!("reviews", "live", by: "system")

      expect { expect(described_class.change!("reviews", "live", by: "1")).to be_nil }
        .not_to change(FeatureFlagChange, :count)
    end

    it "changes and logs nothing for Preview on a Feature with no stored state, which already reads as Preview" do
      expect(described_class.change!("reviews", "preview", by: "1")).to be_nil

      expect(described_class.where(key: "reviews")).not_to exist
      expect(FeatureFlagChange.where(feature_key: "reviews")).not_to exist
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

  # Two staff members setting a Feature with no stored state at once must
  # not fail on the unique key: one stores it, the other then changes it.
  describe ".change! racing on a Feature with no stored state" do
    self.use_transactional_tests = false

    after do
      FeatureFlagChange.where(feature_key: "suggestions").delete_all
      described_class.where(key: "suggestions").delete_all
    end

    it "stores one row and logs each real change" do
      ready = Queue.new
      go = Queue.new
      threads = %w[live off live off].map do |state|
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            ready << true
            go.pop
            described_class.change!("suggestions", state, by: "1")
          end
        end
      end
      4.times { ready.pop }
      4.times { go << true }

      expect { threads.each(&:join) }.not_to raise_error
      expect(described_class.where(key: "suggestions").count).to eq(1)
      expect(FeatureFlagChange.where(feature_key: "suggestions").order(:id).pluck(:to_state).last)
        .to eq(Features.state("suggestions"))
      expect(FeatureFlagChange.where(feature_key: "suggestions", from_state: nil).count).to eq(1)
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
