# frozen_string_literal: true

require "rails_helper"

RSpec.describe Achievement do
  it "is unique per set and external id" do
    existing = create(:achievement)
    duplicate = build(:achievement, achievement_set: existing.achievement_set, external_id: existing.external_id)

    expect(duplicate).not_to be_valid
    expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    expect(build(:achievement, external_id: existing.external_id)).to be_valid
  end

  it "rejects an unknown tier" do
    expect(build(:achievement, tier: "diamond")).not_to be_valid
  end

  describe ".active" do
    it "excludes removed Achievements" do
      set = create(:achievement_set)
      kept = create(:achievement, achievement_set: set)
      create(:achievement, achievement_set: set, removed_at: Time.current)

      expect(set.achievements.active).to eq([ kept ])
    end
  end
end
