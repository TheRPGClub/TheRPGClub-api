# frozen_string_literal: true

require "rails_helper"

RSpec.describe UserAchievementUnlock do
  let(:at) { Time.utc(2026, 11, 1, 12) }

  it "records one Unlock per member per Achievement" do
    existing = create(:user_achievement_unlock)
    duplicate = build(:user_achievement_unlock, linked_account: existing.linked_account,
      achievement: existing.achievement)

    expect(duplicate).not_to be_valid
    expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  describe ".classify_highlight" do
    def set(provider)
      build(:achievement_set, provider: provider)
    end

    def unlock_of(achievement, hardcore: false)
      build(:user_achievement_unlock, achievement: achievement, unlocked_at: at, hardcore: hardcore)
    end

    def progress(completed_at: nil, mastered_at: nil)
      build(:user_achievement_set_progress, completed_at: completed_at, mastered_at: mastered_at)
    end

    it "returns nil for an ordinary Unlock" do
      unlock = unlock_of(build(:achievement, achievement_set: set("steam"), rarity: 5.0))

      expect(described_class.classify_highlight(unlock, progress_after: progress)).to be_nil
    end

    it "marks an Unlock under 5% Rarity as rare" do
      unlock = unlock_of(build(:achievement, achievement_set: set("steam"), rarity: 4.99))

      expect(described_class.classify_highlight(unlock, progress_after: progress)).to eq("rare")
    end

    it "ignores a missing Rarity" do
      unlock = unlock_of(build(:achievement, achievement_set: set("steam"), rarity: nil))

      expect(described_class.classify_highlight(unlock, progress_after: progress)).to be_nil
    end

    it "prefers completion over rare for the Unlock that completes the set" do
      unlock = unlock_of(build(:achievement, achievement_set: set("steam"), rarity: 1.0))

      expect(described_class.classify_highlight(unlock, progress_after: progress(completed_at: at)))
        .to eq("completion")
    end

    it "does not mark an earlier Unlock as the completion" do
      unlock = unlock_of(build(:achievement, achievement_set: set("steam"), rarity: 50.0))

      expect(described_class.classify_highlight(unlock, progress_after: progress(completed_at: at + 1.hour)))
        .to be_nil
    end

    it "prefers mastery over completion for a hardcore RA Unlock" do
      unlock = unlock_of(build(:achievement, achievement_set: set("retroachievements"), rarity: 1.0),
        hardcore: true)

      expect(described_class.classify_highlight(unlock,
        progress_after: progress(completed_at: at, mastered_at: at))).to eq("mastery")
    end

    it "marks a softcore RA completion as completion" do
      unlock = unlock_of(build(:achievement, achievement_set: set("retroachievements"), rarity: 50.0))

      expect(described_class.classify_highlight(unlock, progress_after: progress(completed_at: at)))
        .to eq("completion")
    end

    it "prefers platinum over everything else" do
      unlock = unlock_of(build(:achievement, achievement_set: set("psn"), tier: "platinum", rarity: 1.0))

      expect(described_class.classify_highlight(unlock, progress_after: progress(completed_at: at)))
        .to eq("platinum")
    end
  end

  describe ".of_active_members" do
    it "excludes departed members and bots" do
      kept = create(:user_achievement_unlock)
      departed = create(:user_achievement_unlock)
      departed.user.update!(server_left_at: Time.current)

      expect(described_class.of_active_members.where(id: [ kept.id, departed.id ])).to eq([ kept ])
    end
  end
end
