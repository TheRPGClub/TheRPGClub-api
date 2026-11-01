# frozen_string_literal: true

require "rails_helper"

RSpec.describe UserLinkedAccount do
  let(:user) { create(:user) }

  describe "uniqueness" do
    it "lets one member claim a Provider identity" do
      existing = create(:user_linked_account, provider: "steam")
      duplicate = build(:user_linked_account, provider: "steam", external_id: existing.external_id)

      expect(duplicate).not_to be_valid
      expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "allows the same external id on different Providers" do
      existing = create(:user_linked_account, provider: "steam")

      expect(build(:user_linked_account, provider: "psn", external_id: existing.external_id)).to be_valid
    end

    it "gives a member one Linked Account per Provider" do
      create(:user_linked_account, user: user, provider: "retroachievements")
      second = build(:user_linked_account, user: user, provider: "retroachievements")

      expect(second).not_to be_valid
      expect { second.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "rejects an unknown Provider" do
      expect(build(:user_linked_account, provider: "xbox")).not_to be_valid
    end
  end

  describe "unlinking" do
    it "removes the account's Unlocks and progress and keeps the Sets and Achievements" do
      account = create(:user_linked_account, user: user, provider: "steam")
      set = create(:achievement_set, provider: "steam")
      achievement = create(:achievement, achievement_set: set)
      create(:user_achievement_unlock, linked_account: account, achievement: achievement)
      create(:user_achievement_set_progress, linked_account: account, achievement_set: set)

      account.destroy!

      expect(UserAchievementUnlock.where(user_id: user.user_id)).to be_empty
      expect(UserAchievementSetProgress.where(user_id: user.user_id)).to be_empty
      expect(AchievementSet.exists?(set.id)).to be(true)
      expect(Achievement.exists?(achievement.id)).to be(true)
    end
  end

  describe ".sync_due" do
    let(:now) { Time.utc(2026, 11, 1, 6) }

    it "returns the Provider's accounts whose sync is due, oldest first" do
      later = create(:user_linked_account, provider: "psn", sync_due_at: now - 1.minute)
      older = create(:user_linked_account, provider: "psn", sync_due_at: now - 1.hour)
      create(:user_linked_account, provider: "psn", sync_due_at: now + 1.minute)
      create(:user_linked_account, provider: "psn", sync_due_at: nil)
      create(:user_linked_account, provider: "steam", sync_due_at: now - 2.hours)

      expect(described_class.sync_due("psn", now)).to eq([ older, later ])
    end
  end
end
