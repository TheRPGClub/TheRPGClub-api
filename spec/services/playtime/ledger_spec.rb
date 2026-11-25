# frozen_string_literal: true

require "rails_helper"

# Playtime::Ledger (spec api#457, ADR 0015): the one place a member's Playtime
# for a game is worked out, for one game or a batch.
RSpec.describe Playtime::Ledger do
  let(:member) { create(:user) }
  let(:game) { create(:game) }
  let!(:windows) { create(:platform, platform_name: "PC (Microsoft Windows)") }
  let!(:snes) { create(:platform, platform_name: "Super Nintendo Entertainment System") }
  let!(:switch) { create(:platform, platform_name: "Nintendo Switch") }

  def provider_set(user, provider:, minutes:, game: self.game, label: nil)
    account = UserLinkedAccount.find_by(user_id: user.user_id, provider: provider) ||
      create(:user_linked_account, user: user, provider: provider)
    label ||= { "steam" => "PC", "retroachievements" => "SNES/Super Famicom", "psn" => "PS5" }.fetch(provider)
    set = create(:achievement_set, provider: provider, game: game, platform_label: label)
    create(:user_achievement_set_progress, linked_account: account, achievement_set: set, playtime_minutes: minutes)
  end

  describe ".for_game" do
    it "sums Steam, RetroAchievements and Manual figures" do
      provider_set(member, provider: "steam", minutes: 600)
      provider_set(member, provider: "retroachievements", minutes: 120)
      create(:manual_playtime, user: member, game: game, platform: switch, minutes: 30)

      playtime = described_class.for_game(user_id: member.user_id, game_id: game.game_id)

      expect(playtime.total_minutes).to eq(750)
      expect(playtime.provider_sets.map { |set| [ set.provider, set.platform_id, set.minutes ] })
        .to contain_exactly([ "steam", windows.platform_id, 600 ], [ "retroachievements", snes.platform_id, 120 ])
      expect(playtime.manual_entries.map { |entry| [ entry.platform_id, entry.minutes ] })
        .to eq([ [ switch.platform_id, 30 ] ])
    end

    it "counts nothing for an unmapped set or another member's time" do
      provider_set(member, provider: "steam", minutes: 600, game: nil)
      provider_set(create(:user), provider: "steam", minutes: 90)

      playtime = described_class.for_game(user_id: member.user_id, game_id: game.game_id)

      expect(playtime.total_minutes).to eq(0)
      expect(playtime.provider_sets).to be_empty
    end

    it "shows an unresolved platform label raw and never reports a mismatch for it" do
      provider_set(member, provider: "psn", minutes: 50, label: "PS5,PS4")
      create(:manual_playtime, user: member, game: game, platform: nil, minutes: 10)

      playtime = described_class.for_game(user_id: member.user_id, game_id: game.game_id)

      expect(playtime.provider_sets.first).to have_attributes(platform_id: nil, platform_label: "PS5,PS4", counted: true)
      expect(playtime.mismatches).to be_empty
      expect(playtime.total_minutes).to eq(60)
    end

    it "reports a mismatch when a Provider and a Manual entry share a resolved platform" do
      provider_set(member, provider: "steam", minutes: 600)
      entry = create(:manual_playtime, user: member, game: game, platform: windows, minutes: 500)

      playtime = described_class.for_game(user_id: member.user_id, game_id: game.game_id)

      expect(playtime.total_minutes).to eq(1100)
      expect(playtime.mismatches.map(&:to_h)).to eq([ {
        platform_id: windows.platform_id, provider: "steam", provider_minutes: 600,
        manual_playtime_id: entry.id, manual_minutes: 500
      } ])
    end

    it "shows but does not count a Provider figure the member kept their own entry over" do
      provider_set(member, provider: "steam", minutes: 600)
      create(:manual_playtime, user: member, game: game, platform: windows, minutes: 500, keeps_over_provider: "steam")

      playtime = described_class.for_game(user_id: member.user_id, game_id: game.game_id)

      expect(playtime.total_minutes).to eq(500)
      expect(playtime.provider_sets.first).to have_attributes(minutes: 600, counted: false)
      expect(playtime.mismatches).to be_empty
    end
  end

  # PSN Playtime (ticket api#463): the set's trophyTitlePlatform is the label.
  describe "PSN figures" do
    let!(:ps5) { create(:platform, platform_name: "PlayStation 5") }
    let!(:ps4) { create(:platform, platform_name: "PlayStation 4") }

    it "resolve PS4 and PS5 labels, and meet a Manual entry on the same platform as a mismatch" do
      provider_set(member, provider: "psn", minutes: 7080, label: "PS5")
      provider_set(member, provider: "psn", minutes: 200, label: "PS4")
      entry = create(:manual_playtime, user: member, game: game, platform: ps5, minutes: 7200)

      playtime = described_class.for_game(user_id: member.user_id, game_id: game.game_id)

      expect(playtime.provider_sets.map { |set| [ set.provider, set.platform_id, set.minutes ] })
        .to contain_exactly([ "psn", ps5.platform_id, 7080 ], [ "psn", ps4.platform_id, 200 ])
      expect(playtime.total_minutes).to eq(14_480)
      expect(playtime.mismatches.map(&:to_h)).to eq([ {
        platform_id: ps5.platform_id, provider: "psn", provider_minutes: 7080,
        manual_playtime_id: entry.id, manual_minutes: 7200
      } ])
    end

    it "stop counting on the platform the member kept their own entry for" do
      provider_set(member, provider: "psn", minutes: 7080, label: "PS5")
      provider_set(member, provider: "psn", minutes: 200, label: "PS4")
      create(:manual_playtime, user: member, game: game, platform: ps5, minutes: 7200, keeps_over_provider: "psn")

      playtime = described_class.for_game(user_id: member.user_id, game_id: game.game_id)

      expect(playtime.total_minutes).to eq(7400)
      expect(playtime.provider_sets.to_h { |set| [ set.platform_id, set.counted ] })
        .to eq(ps5.platform_id => false, ps4.platform_id => true)
      expect(playtime.mismatches).to be_empty
    end
  end

  describe "batches" do
    it "works out many games for one member, and one game for many members, in one query" do
      other_game = create(:game)
      friend = create(:user)
      provider_set(member, provider: "steam", minutes: 100)
      provider_set(member, provider: "steam", minutes: 40, game: other_game)
      create(:manual_playtime, user: friend, game: game, minutes: 7)
      create(:manual_playtime, user: member, game: other_game, minutes: 2)

      by_game = nil
      queries = count_queries { by_game = described_class.new(user_ids: [ member.user_id ]).minutes_by_game(member.user_id) }
      by_member = described_class.new(game_ids: [ game.game_id ]).minutes_by_user(game.game_id)

      expect(by_game).to eq(game.game_id => 100, other_game.game_id => 42)
      expect(by_member).to eq(member.user_id => 100, friend.user_id => 7)
      expect(queries).to be <= 3 # the rows, the open Playthroughs, and the platforms the labels resolve against
    end

    it "carries each member's open Playthrough and its time, even on a game with no Playtime" do
      other_game = create(:game)
      create(:manual_playtime, user: member, game: game, minutes: 500)
      create(:playthrough, user: member, game: game, baseline_minutes: 420)
      create(:playthrough, user: member, game: game, baseline_minutes: 0, ended_at: 1.day.ago,
        end_reason: "abandoned", final_minutes: 10)
      fresh = create(:playthrough, user: member, game: other_game)

      ledger = described_class.new(user_ids: [ member.user_id ], game_ids: [ game.game_id, other_game.game_id ])

      expect(ledger.for(member.user_id, game.game_id).playthrough_minutes).to eq(80)
      expect(ledger.for(member.user_id, other_game.game_id)).to have_attributes(open_playthrough: fresh,
        playthrough_minutes: 0, total_minutes: 0)
      expect(ledger.minutes_by_game(member.user_id)).to eq(game.game_id => 500)
    end

    it "has no Playthrough time when none is open" do
      expect(described_class.for_game(user_id: member.user_id, game_id: game.game_id).playthrough_minutes).to be_nil
    end
  end

  def count_queries(&)
    count = 0
    counter = ->(*, payload) { count += 1 unless payload[:name] == "SCHEMA" || payload[:cached] }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &)
    count
  end
end
