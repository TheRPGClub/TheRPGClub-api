# frozen_string_literal: true

require "rails_helper"

RSpec.describe Achievements::SyncSet do
  include ActiveSupport::Testing::TimeHelpers

  let(:now) { Time.utc(2026, 11, 1, 12) }
  let(:listed_at) { now - 10.minutes }
  let(:client) { double("Provider client") } # rubocop:disable RSpec/VerifiedDoubles

  around { |example| travel_to(now) { example.run } }

  before do
    UserLinkedAccount::PROVIDERS.each do |provider|
      allow(Achievements::Providers).to receive(:client_for).with(provider).and_return(client)
    end
  end

  def account_for(provider, mode: "incremental", **attributes)
    create(:user_linked_account, provider: provider, sync_mode: mode, sync_status: mode == "backfill" ? "pending" : "ok",
      **attributes)
  end

  def pending_row(account, set, **attributes)
    create(:user_achievement_set_progress, linked_account: account, achievement_set: set, synced_at: nil,
      sync_pending_at: listed_at, **attributes)
  end

  def definition(external_id, **attributes)
    Achievements::Providers::AchievementDefinition.new(external_id: external_id, name: "Ach #{external_id}",
      rarity: 50.0, **attributes)
  end

  def unlock(external_id, at, hardcore: false)
    Achievements::Providers::ProviderUnlock.new(achievement_external_id: external_id, unlocked_at: at,
      hardcore_unlocked_at: (at if hardcore))
  end

  def set_definition(set, achievements:, unlocks: [], **attributes)
    Achievements::Providers::SetDefinition.new(external_id: set.external_id, achievements: achievements,
      unlocks: unlocks, **{ title: nil }.merge(attributes))
  end

  def unlock_of(account, external_id)
    UserAchievementUnlock.joins(:achievement).find_by!(user_id: account.user_id,
      achievements: { external_id: external_id })
  end

  describe "an import" do
    let(:account) { account_for("steam") }
    let(:set) { create(:achievement_set, provider: "steam", external_id: "440", title: "Listed Title") }
    let!(:row) { pending_row(account, set, playtime_minutes: 120) }

    before do
      allow(client).to receive(:set_with_progress).with(account.external_id, "440").and_return(
        set_definition(set,
          achievements: [ definition("a", display_order: 1, icon_url: "https://img/a.jpg", hidden: true),
                          definition("b", display_order: 2) ],
          unlocks: [ unlock("a", now - 30.days) ], title: "Schema Title")
      )
    end

    it "upserts the shared definitions and the member's Unlocks" do
      described_class.call(row)

      expect(set.achievements.order(:display_order).pluck(:external_id, :icon_url, :hidden))
        .to eq([ [ "a", "https://img/a.jpg", true ], [ "b", nil, false ] ])
      expect(unlock_of(account, "a")).to have_attributes(unlocked_at: now - 30.days, hardcore: false,
        user_linked_account_id: account.id)
      expect(set.reload).to have_attributes(achievements_count: 2, definitions_synced_at: now)
    end

    it "recomputes the cached progress, keeps the listed title and playtime, and clears the pending marker" do
      described_class.call(row)

      expect(row.reload).to have_attributes(earned_count: 1, total_count: 2, synced_at: now, sync_pending_at: nil,
        playtime_minutes: 120)
      expect(set.reload.title).to eq("Listed Title")
    end

    it "finishes the account once its last pending set is imported" do
      described_class.call(row)

      expect(account.reload).to have_attributes(last_synced_at: listed_at, sync_status: "ok", sync_mode: "incremental")
    end
  end

  describe "a Backfill" do
    let(:account) { account_for("steam", mode: "backfill") }
    let(:first_set) { create(:achievement_set, provider: "steam") }
    let(:second_set) { create(:achievement_set, provider: "steam") }
    let!(:first_row) { pending_row(account, first_set) }
    let!(:second_row) { pending_row(account, second_set) }

    before do
      [ first_set, second_set ].each do |set|
        allow(client).to receive(:set_with_progress).with(account.external_id, set.external_id).and_return(
          set_definition(set, achievements: [ definition("rare", rarity: 1.0) ], unlocks: [ unlock("rare", now - 1.hour) ])
        )
      end
    end

    it "creates Unlocks that are classified but never announceable" do
      described_class.call(first_row)

      expect(UserAchievementUnlock.where(user_id: account.user_id).pluck(:highlight, :announceable))
        .to eq([ [ "completion", false ] ])
    end

    it "stamps backfilled_at only after the last set" do
      described_class.call(first_row)
      expect(account.reload).to have_attributes(backfilled_at: nil, sync_status: "pending", sync_mode: "backfill")

      described_class.call(second_row)
      expect(account.reload).to have_attributes(backfilled_at: now, last_synced_at: listed_at, sync_status: "ok",
        sync_mode: "incremental")
    end
  end

  describe "an incremental sync's Highlights" do
    let(:account) { account_for("psn") }
    let(:set) { create(:achievement_set, provider: "psn", external_id: "NPWR1_00", np_service_name: "trophy2") }
    let!(:row) { pending_row(account, set) }

    before do
      allow(client).to receive(:set_with_progress).with(account.external_id, "NPWR1_00", "trophy2").and_return(
        set_definition(set,
          achievements: [ definition("0", tier: "platinum", display_order: 0),
                          definition("1", tier: "gold", rarity: 2.5, display_order: 1),
                          definition("2", tier: "bronze", rarity: 1.0, display_order: 2),
                          definition("3", tier: "bronze", display_order: 3),
                          definition("4", tier: "bronze", display_order: 4) ],
          unlocks: [ unlock("0", now - 1.hour), unlock("1", now - 2.hours), unlock("2", now - 3.days),
                     unlock("3", now - 4.days) ])
      )
    end

    it "announces a fresh platinum and a fresh rare Unlock" do
      described_class.call(row)

      expect(unlock_of(account, "0")).to have_attributes(highlight: "platinum", announceable: true)
      expect(unlock_of(account, "1")).to have_attributes(highlight: "rare", announceable: true)
    end

    it "classifies a 3-day-old rare Unlock without announcing it" do
      described_class.call(row)

      expect(unlock_of(account, "2")).to have_attributes(highlight: "rare", announceable: false)
      expect(unlock_of(account, "3")).to have_attributes(highlight: nil, announceable: false)
    end

    it "never reclassifies an Unlock it already holds" do
      described_class.call(row)
      unlock_of(account, "1").update!(highlight: nil, announceable: false)
      row.update!(sync_pending_at: now)

      described_class.call(row.reload)

      expect(unlock_of(account, "1")).to have_attributes(highlight: nil, announceable: false)
    end
  end

  describe "Completion and Mastery" do
    def import(provider, unlocks, definitions: nil)
      account = account_for(provider)
      set = create(:achievement_set, provider: provider)
      row = pending_row(account, set)
      definitions ||= [ definition("1", display_order: 1), definition("2", display_order: 2) ]
      allow(client).to receive(:set_with_progress).with(account.external_id, set.external_id)
        .and_return(set_definition(set, achievements: definitions, unlocks: unlocks))
      described_class.call(row)
      account
    end

    it "marks the Unlock that completes a set as its Completion" do
      account = import("steam", [ unlock("1", now - 2.hours), unlock("2", now - 1.hour) ])

      expect(unlock_of(account, "2")).to have_attributes(highlight: "completion", announceable: true)
      expect(unlock_of(account, "1").highlight).to be_nil
      expect(account.set_progress.first.completed_at).to eq(now - 1.hour)
    end

    it "marks an all-hardcore RA set's last Unlock as its Mastery" do
      account = import("retroachievements",
        [ unlock("1", now - 2.hours, hardcore: true), unlock("2", now - 1.hour, hardcore: true) ])

      expect(unlock_of(account, "2")).to have_attributes(highlight: "mastery", hardcore: true, announceable: true)
    end

    it "marks a softcore RA set's last Unlock as its Completion" do
      account = import("retroachievements",
        [ unlock("1", now - 2.hours, hardcore: true), unlock("2", now - 1.hour) ])

      expect(unlock_of(account, "2").highlight).to eq("completion")
    end

    it "gives the Completion to one Unlock only when several share the completing time" do
      at = now - 1.hour
      definitions = [ definition("1", display_order: 1, rarity: 1.0), definition("2", display_order: 2) ]
      account = import("steam", [ unlock("1", at), unlock("2", at) ], definitions: definitions)

      expect(unlock_of(account, "2").highlight).to eq("completion")
      expect(unlock_of(account, "1").highlight).to eq("rare")
    end

    it "upgrades a softcore RA Unlock to hardcore without announcing it again" do
      account = account_for("retroachievements")
      set = create(:achievement_set, provider: "retroachievements")
      row = pending_row(account, set)
      definitions = [ definition("1", display_order: 1, rarity: 1.0), definition("2", display_order: 2) ]
      allow(client).to receive(:set_with_progress).and_return(
        set_definition(set, achievements: definitions, unlocks: [ unlock("1", now - 1.hour) ])
      )
      described_class.call(row)
      unlock_of(account, "1").update!(announceable: false) # the bot has posted it

      allow(client).to receive(:set_with_progress).and_return(
        set_definition(set, achievements: definitions, unlocks: [ unlock("1", now - 1.hour, hardcore: true) ])
      )
      row.update!(sync_pending_at: now)
      described_class.call(row.reload)

      expect(unlock_of(account, "1")).to have_attributes(hardcore: true, highlight: "rare", announceable: false)
      expect(row.reload.hardcore_earned_count).to eq(1)
    end
  end

  describe "removed Achievements" do
    let(:set) { create(:achievement_set, provider: "steam") }
    let(:account) { account_for("steam") }
    let(:other_account) { account_for("steam") }
    let!(:row) { pending_row(account, set) }
    let!(:dropped) { create(:achievement, achievement_set: set, external_id: "dropped") }
    let!(:other_unlock) { create(:user_achievement_unlock, linked_account: other_account, achievement: dropped) }

    it "soft-removes an Achievement the Provider stops reporting, keeping every member's Unlocks of it" do
      allow(client).to receive(:set_with_progress)
        .and_return(set_definition(set, achievements: [ definition("kept") ]))

      described_class.call(row)

      expect(dropped.reload.removed_at).to eq(now)
      expect(other_unlock.reload).to be_persisted
      expect(set.reload.achievements_count).to eq(1)
      expect(row.reload.total_count).to eq(1)
    end

    it "restores an Achievement that reappears" do
      dropped.update!(removed_at: now - 1.day)
      allow(client).to receive(:set_with_progress)
        .and_return(set_definition(set, achievements: [ definition("dropped") ]))

      described_class.call(row)

      expect(dropped.reload.removed_at).to be_nil
    end

    it "removes nothing when the Provider reports an empty set" do
      allow(client).to receive(:set_with_progress).and_return(set_definition(set, achievements: []))

      described_class.call(row)

      expect(dropped.reload.removed_at).to be_nil
      expect(row.reload).to have_attributes(sync_pending_at: nil, synced_at: nil)
    end

    it "treats a set the Provider has no stats for (nil) as no set" do
      allow(client).to receive(:set_with_progress).and_return(nil)

      described_class.call(row)

      expect(dropped.reload.removed_at).to be_nil
      expect(row.reload).to have_attributes(sync_pending_at: nil, synced_at: nil)
      expect(account.reload.last_synced_at).to eq(listed_at)
    end
  end

  it "shares one set's definitions between two members" do
    set = create(:achievement_set, provider: "retroachievements", external_id: "1")
    first = account_for("retroachievements")
    second = account_for("retroachievements")
    allow(client).to receive(:set_with_progress).and_return(
      set_definition(set, achievements: [ definition("10", points: 5), definition("11", points: 10) ],
        unlocks: [ unlock("10", now - 1.day) ], playtime_minutes: 42)
    )

    described_class.call(pending_row(first, set))
    expect { described_class.call(pending_row(second, set)) }.not_to change(Achievement, :count)

    expect(set.achievements.count).to eq(2)
    expect(UserAchievementUnlock.where(achievement: set.achievements).pluck(:user_id))
      .to contain_exactly(first.user_id, second.user_id)
    expect(set.reload.points_total).to eq(15)
    expect(UserAchievementSetProgress.find_by!(user_id: second.user_id)).to have_attributes(points_earned: 5,
      playtime_minutes: 42)
  end

  it "stores an Unlock the Provider gives no time for at the unknown-time sentinel, unannounced" do
    account = account_for("steam")
    set = create(:achievement_set, provider: "steam")
    row = pending_row(account, set)
    allow(client).to receive(:set_with_progress).and_return(
      set_definition(set, achievements: [ definition("a", rarity: 1.0), definition("b") ], unlocks: [ unlock("a", nil) ])
    )

    described_class.call(row)

    expect(unlock_of(account, "a")).to have_attributes(unlocked_at: described_class::UNKNOWN_UNLOCK_TIME,
      announceable: false)
  end

  describe "errors" do
    let(:account) { account_for("steam") }
    let(:set) { create(:achievement_set, provider: "steam") }
    let!(:row) { pending_row(account, set) }
    let!(:other_row) { pending_row(account, create(:achievement_set, provider: "steam")) }

    it "stops a private account and clears every pending marker" do
      allow(client).to receive(:set_with_progress).and_raise(Achievements::Providers::Private, "private")

      described_class.call(row)

      expect(account.reload).to have_attributes(sync_status: "private", sync_error: "private", sync_due_at: nil)
      expect([ row.reload.sync_pending_at, other_row.reload.sync_pending_at ]).to eq([ nil, nil ])
    end

    it "stops an account the Provider no longer knows" do
      allow(client).to receive(:set_with_progress).and_raise(Achievements::Providers::NotFound, "gone")

      described_class.call(row)

      expect(account.reload.sync_status).to eq("not_found")
      expect(other_row.reload.sync_pending_at).to be_nil
    end

    [ Achievements::Providers::RateLimited.new(retry_after: 30), Achievements::Providers::AuthExpired.new("npsso") ]
      .each do |error|
      it "re-raises #{error.class.name.demodulize} and leaves the state unchanged" do
        allow(client).to receive(:set_with_progress).and_raise(error)
        before = [ account.reload.attributes, row.reload.attributes ]

        expect { described_class.call(row) }.to raise_error(error.class)
        expect([ account.reload.attributes, row.reload.attributes ]).to eq(before)
      end
    end

    it "marks any other failure as an error and clears only this set's marker" do
      allow(client).to receive(:set_with_progress).and_raise(RuntimeError, "boom")

      described_class.call(row)

      expect(account.reload).to have_attributes(sync_status: "error", sync_error: "boom")
      expect(row.reload.sync_pending_at).to be_nil
      expect(other_row.reload.sync_pending_at).to eq(listed_at)
    end
  end
end
