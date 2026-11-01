# frozen_string_literal: true

require "rails_helper"

# Behavior specs for the community feed (api-09). `latest` groups Unlocks into
# cards per member + Achievement Set + UTC day of `unlocked_at` (up to 8
# Unlocks each), newest first; `highlights` is one card per Highlight Unlock.
# Departed members and removed Achievements never appear.
RSpec.describe "api/v1 achievement feed behavior", type: :request do
  let(:viewer) { create(:user) }
  let(:alice) { create(:user) }
  let(:bob) { create(:user) }
  let(:alice_steam) { create(:user_linked_account, user: alice, provider: "steam") }
  let(:bob_psn) { create(:user_linked_account, user: bob, provider: "psn") }
  let(:steam_set) { create(:achievement_set, provider: "steam") }
  let(:psn_set) { create(:achievement_set, provider: "psn") }

  def unlock(account, set, at, **attrs)
    achievement = create(:achievement, achievement_set: set, **attrs.slice(:removed_at, :tier, :hidden))
    create(:user_achievement_unlock, linked_account: account, user: account.user, achievement: achievement,
      unlocked_at: at, **attrs.except(:removed_at, :tier, :hidden))
  end

  def feed(**params)
    get "/api/v1/achievements/feed", params: params, headers: auth_headers_for(viewer)
    expect(response).to have_http_status(:ok)
    json
  end

  describe "view=latest" do
    it "groups Unlocks per member, set and UTC day, newest first, splitting across midnight UTC" do
      late = unlock(alice_steam, steam_set, Time.utc(2026, 10, 1, 23, 30))
      early = unlock(alice_steam, steam_set, Time.utc(2026, 10, 1, 1, 0))
      after_midnight = unlock(alice_steam, steam_set, Time.utc(2026, 10, 2, 0, 30))
      bob_one = unlock(bob_psn, psn_set, Time.utc(2026, 10, 1, 12, 0))

      body = feed(view: "latest")

      cards = body.fetch("data")
      expect(cards.map { |c| [ c.dig("user", "user_id"), c.dig("achievement_set", "id"), c.fetch("day"), c.fetch("count") ] })
        .to eq([
          [ alice.user_id, steam_set.id, "2026-10-02", 1 ],
          [ alice.user_id, steam_set.id, "2026-10-01", 2 ],
          [ bob.user_id, psn_set.id, "2026-10-01", 1 ]
        ])
      expect(cards.first).to include("kind" => "group")
      expect(cards.first.fetch("unlocks").map { |u| u.fetch("id") }).to eq([ after_midnight.id ])
      expect(cards.second.fetch("unlocks").map { |u| u.fetch("id") }).to eq([ late.id, early.id ])
      expect(cards.second.fetch("latest_unlocked_at")).to eq(late.unlocked_at.utc.iso8601(3))
      expect(cards.third.fetch("unlocks").first.fetch("achievement")).to include("id" => bob_one.achievement_id)
      expect(body.fetch("meta")).to include("count" => 3)
    end

    it "caps a card at 8 Unlocks but counts them all" do
      day = Time.utc(2026, 10, 1)
      10.times { |i| unlock(alice_steam, steam_set, day + i.minutes) }

      card = feed.fetch("data").sole

      expect(card.fetch("count")).to eq(10)
      expect(card.fetch("unlocks").size).to eq(8)
    end

    it "paginates groups with an explicit group count" do
      5.times { |i| unlock(alice_steam, steam_set, Time.utc(2026, 10, 1) + i.days) }

      body = feed(per: 2, page: 3)

      expect(body.fetch("data").map { |c| c.fetch("day") }).to eq([ "2026-10-01" ])
      expect(body.fetch("meta")).to include("count" => 5, "pages" => 3, "page" => 3)
    end

    it "filters by Provider" do
      unlock(alice_steam, steam_set, 1.day.ago)
      unlock(bob_psn, psn_set, 1.day.ago)

      expect(feed(provider: "psn").fetch("data").map { |c| c.dig("user", "user_id") }).to eq([ bob.user_id ])
    end

    it "excludes departed members and removed Achievements" do
      unlock(alice_steam, steam_set, 1.day.ago)
      unlock(bob_psn, psn_set, 1.day.ago, removed_at: 1.hour.ago)
      alice.update!(server_left_at: 1.hour.ago)

      body = feed

      expect(body.fetch("data")).to be_empty
      expect(body.dig("meta", "count")).to eq(0)
    end

    it "marks the Unlocks the viewer also has" do
      mine = unlock(alice_steam, steam_set, 1.day.ago, hidden: true)
      create(:user_achievement_unlock, linked_account: create(:user_linked_account, user: viewer),
        user: viewer, achievement: mine.achievement)

      unlocks = feed.fetch("data").flat_map { |c| c.fetch("unlocks") }
        .select { |u| u.dig("achievement", "id") == mine.achievement_id }

      expect(unlocks.map { |u| [ u.fetch("user_id"), u.fetch("viewer_unlocked") ] })
        .to contain_exactly([ alice.user_id, true ], [ viewer.user_id, true ])
    end

    it "loads a page in a fixed number of queries, however many cards it has" do
      headers = auth_headers_for(viewer)
      count_queries = lambda do
        queries = 0
        subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
          # Cached hits count too, so the query cache cannot mask a per-card query.
          queries += 1 unless payload[:name] == "SCHEMA"
        end
        begin
          get "/api/v1/achievements/feed", headers: headers
        ensure
          ActiveSupport::Notifications.unsubscribe(subscriber)
        end
        expect(response).to have_http_status(:ok)
        queries
      end

      unlock(alice_steam, steam_set, 2.days.ago)
      small = count_queries.call

      5.times do |i|
        account = create(:user_linked_account, provider: "psn")
        set = create(:achievement_set, provider: "psn")
        3.times { unlock(account, set, (i + 1).hours.ago) }
      end
      large = count_queries.call

      expect(feed.fetch("data").size).to eq(6)
      expect(large).to eq(small)
    end
  end

  describe "view=highlights" do
    it "lists one card per Highlight Unlock, newest first" do
      platinum = unlock(bob_psn, psn_set, 1.hour.ago, highlight: "platinum", tier: "platinum")
      rare = unlock(alice_steam, steam_set, 2.hours.ago, highlight: "rare")
      unlock(alice_steam, steam_set, 30.minutes.ago)
      unlock(alice_steam, steam_set, 3.hours.ago, highlight: "rare", removed_at: 1.hour.ago)

      cards = feed(view: "highlights").fetch("data")

      expect(cards.map { |c| c.fetch("id") }).to eq([ platinum.id, rare.id ])
      expect(cards.first).to include("kind" => "highlight", "highlight" => "platinum")
      expect(cards.first.fetch("user")).to include("user_id" => bob.user_id)
      expect(cards.first.fetch("achievement")).to include("tier" => "platinum")
      expect(cards.first.fetch("achievement_set")).to include("id" => psn_set.id)
    end

    it "filters by Provider and excludes departed members" do
      unlock(bob_psn, psn_set, 1.hour.ago, highlight: "completion")
      unlock(alice_steam, steam_set, 1.hour.ago, highlight: "rare")

      expect(feed(view: "highlights", provider: "steam").fetch("data").map { |c| c.dig("user", "user_id") })
        .to eq([ alice.user_id ])

      alice.update!(server_left_at: 1.hour.ago)
      expect(feed(view: "highlights", provider: "steam").fetch("data")).to be_empty
    end
  end

  it "rejects an unknown view or Provider" do
    get "/api/v1/achievements/feed", params: { view: "bogus" }, headers: auth_headers_for(viewer)
    expect(response).to have_http_status(:unprocessable_content)

    get "/api/v1/achievements/feed", params: { provider: "xbox" }, headers: auth_headers_for(viewer)
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "requires authentication" do
    get "/api/v1/achievements/feed"

    expect(response).to have_http_status(:unauthorized)
  end
end
