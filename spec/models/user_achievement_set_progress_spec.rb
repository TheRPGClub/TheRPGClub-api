# frozen_string_literal: true

require "rails_helper"

RSpec.describe UserAchievementSetProgress do
  include ActiveSupport::Testing::TimeHelpers

  let(:now) { Time.utc(2026, 11, 1, 12) }

  def recompute(account, set)
    travel_to(now) { described_class.recompute!(user_id: account.user_id, achievement_set_id: set.id) }
  end

  def unlock(account, achievement, at:, hardcore: false)
    create(:user_achievement_unlock, linked_account: account, achievement: achievement,
      unlocked_at: at, hardcore: hardcore)
  end

  it "gives a member one progress row per set" do
    existing = create(:user_achievement_set_progress)
    duplicate = build(:user_achievement_set_progress, linked_account: existing.linked_account,
      achievement_set: existing.achievement_set)

    expect(duplicate).not_to be_valid
    expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  describe ".recompute!" do
    context "with a partial Steam set" do
      let(:account) { create(:user_linked_account, provider: "steam") }
      let(:set) { create(:achievement_set, provider: "steam") }
      let!(:achievements) { create_list(:achievement, 3, achievement_set: set) }

      it "counts the Unlocks and leaves completion unset" do
        unlock(account, achievements[0], at: now - 3.days)
        unlock(account, achievements[1], at: now - 1.day)

        progress = recompute(account, set)

        expect(progress).to have_attributes(
          user_linked_account_id: account.id,
          earned_count: 2,
          hardcore_earned_count: 0,
          total_count: 3,
          completed_at: nil,
          mastered_at: nil,
          platinum_at: nil,
          last_unlocked_at: now - 1.day,
          synced_at: now
        )
      end

      it "stamps completion with the last Unlock's time once every Achievement is unlocked" do
        unlock(account, achievements[0], at: now - 3.days)
        unlock(account, achievements[2], at: now - 2.days)
        unlock(account, achievements[1], at: now - 5.days)

        progress = recompute(account, set)

        expect(progress).to have_attributes(earned_count: 3, total_count: 3, completed_at: now - 2.days)
      end

      it "excludes removed Achievements from the counts" do
        achievements[2].update!(removed_at: now - 1.week)
        unlock(account, achievements[0], at: now - 3.days)
        unlock(account, achievements[1], at: now - 2.days)
        unlock(account, achievements[2], at: now - 10.days)

        progress = recompute(account, set)

        expect(progress).to have_attributes(earned_count: 2, total_count: 2, completed_at: now - 2.days)
      end

      it "updates the existing row instead of adding one" do
        existing = create(:user_achievement_set_progress, linked_account: account, achievement_set: set,
          synced_at: nil, sync_pending_at: now - 1.minute)
        unlock(account, achievements[0], at: now - 3.days)

        progress = recompute(account, set)

        expect(progress.id).to eq(existing.id)
        expect(progress.reload).to have_attributes(earned_count: 1, synced_at: now)
      end

      it "ignores another member's Unlocks" do
        other = create(:user_linked_account, provider: "steam")
        unlock(other, achievements[0], at: now - 3.days)

        expect(recompute(account, set)).to have_attributes(earned_count: 0, last_unlocked_at: nil)
      end
    end

    context "with a RetroAchievements set" do
      let(:account) { create(:user_linked_account, provider: "retroachievements") }
      let(:set) { create(:achievement_set, provider: "retroachievements") }
      let!(:achievements) do
        [ 5, 10 ].map { |points| create(:achievement, achievement_set: set, points: points) }
      end

      it "stamps Mastery when every Unlock is hardcore" do
        unlock(account, achievements[0], at: now - 2.days, hardcore: true)
        unlock(account, achievements[1], at: now - 1.day, hardcore: true)

        progress = recompute(account, set)

        expect(progress).to have_attributes(
          earned_count: 2, hardcore_earned_count: 2, points_earned: 15,
          completed_at: now - 1.day, mastered_at: now - 1.day
        )
      end

      it "stamps only Completion when an Unlock is softcore" do
        unlock(account, achievements[0], at: now - 2.days, hardcore: true)
        unlock(account, achievements[1], at: now - 1.day, hardcore: false)

        progress = recompute(account, set)

        expect(progress).to have_attributes(
          earned_count: 2, hardcore_earned_count: 1, points_earned: 15,
          completed_at: now - 1.day, mastered_at: nil
        )
      end
    end

    context "with a PSN set" do
      let(:account) { create(:user_linked_account, provider: "psn") }
      let(:set) { create(:achievement_set, provider: "psn") }
      let!(:platinum) { create(:achievement, achievement_set: set, tier: "platinum") }
      let!(:gold) { create(:achievement, achievement_set: set, tier: "gold") }
      let!(:dlc) { create(:achievement, achievement_set: set, tier: "bronze") }

      it "stamps the Platinum without a Completion while DLC is missing" do
        unlock(account, gold, at: now - 3.days)
        unlock(account, platinum, at: now - 2.days)

        progress = recompute(account, set)

        expect(progress).to have_attributes(earned_count: 2, total_count: 3, platinum_at: now - 2.days,
          completed_at: nil, mastered_at: nil)
      end
    end
  end

  describe ".sync_pending" do
    it "returns the Provider's sets waiting for an import, oldest first" do
      psn = create(:user_linked_account, provider: "psn")
      later = create(:user_achievement_set_progress, linked_account: psn, sync_pending_at: now - 1.minute)
      older = create(:user_achievement_set_progress, linked_account: psn, sync_pending_at: now - 1.hour)
      create(:user_achievement_set_progress, linked_account: psn, sync_pending_at: now + 1.minute)
      create(:user_achievement_set_progress, linked_account: psn, sync_pending_at: nil)
      create(:user_achievement_set_progress, linked_account: create(:user_linked_account, provider: "steam"),
        sync_pending_at: now - 2.hours)

      expect(described_class.sync_pending("psn", now)).to eq([ older, later ])
    end
  end

  describe ".synced" do
    it "excludes placeholder rows" do
      synced = create(:user_achievement_set_progress, synced_at: now)
      create(:user_achievement_set_progress, synced_at: nil)

      expect(described_class.synced).to eq([ synced ])
    end
  end

  describe ".of_active_members" do
    it "excludes departed members" do
      kept = create(:user_achievement_set_progress)
      departed = create(:user_achievement_set_progress)
      departed.user.update!(server_left_at: now)

      expect(described_class.of_active_members.where(id: [ kept.id, departed.id ])).to eq([ kept ])
    end
  end
end
