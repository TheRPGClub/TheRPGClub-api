# frozen_string_literal: true

require "rails_helper"

# Behavior specs for the bot's Highlight endpoints: the pending list past the
# stored cursor, the monotonic cursor ack and the PSN auth alert ack.
RSpec.describe "api/v1/achievements highlights behavior", type: :request do
  let(:member) { create(:user, global_name: "Sir Grind") }
  let(:account) { create(:user_linked_account, user: member, provider: "psn") }
  let(:set) { create(:achievement_set, provider: "psn", title: "Elden Ring") }

  def highlight(user: member, linked_account: account, announceable: true, **attrs)
    achievement = create(:achievement, achievement_set: set, rarity: 2.5)
    create(:user_achievement_unlock, user: user, linked_account: linked_account, achievement: achievement,
           highlight: "rare", announceable: announceable, **attrs)
  end

  describe "GET /api/v1/achievements/highlights/pending" do
    it "lists announceable Unlocks with what the post needs" do
      achievement = create(:achievement, achievement_set: set, name: "Elden Lord", tier: "platinum",
                                         icon_url: "https://img/plat.png", rarity: 12.3)
      unlock = create(:user_achievement_unlock, linked_account: account, achievement: achievement,
                                                highlight: "platinum", announceable: true)
      highlight(announceable: false)

      get "/api/v1/achievements/highlights/pending", headers: service_headers

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data").sole).to include(
        "id" => unlock.id, "highlight" => "platinum", "hardcore" => false,
        "user_id" => member.user_id, "display_name" => "Sir Grind",
        "url_path" => "/members/#{member.user_id}/achievements/#{set.id}",
        "achievement" => include("name" => "Elden Lord", "icon_url" => "https://img/plat.png",
                                 "tier" => "platinum", "rarity" => 12.3),
        "achievement_set" => include("id" => set.id, "title" => "Elden Ring", "provider" => "psn")
      )
    end

    it "is forbidden to admins and members" do
      get "/api/v1/achievements/highlights/pending", headers: auth_headers_for(create(:user, role_admin: true))

      expect(response).to have_http_status(:forbidden)
    end

    it "lists only Unlocks past the stored cursor, oldest first" do
      seen = highlight
      first = highlight
      second = highlight
      AchievementHubState.set("bot_highlight_cursor", seen.id)

      get "/api/v1/achievements/highlights/pending", headers: service_headers

      expect(json.fetch("data").pluck("id")).to eq([ first.id, second.id ])
      expect(json.fetch("meta")).to eq("cursor" => seen.id, "next_cursor" => second.id)
    end

    it "caps the list at 25" do
      unlocks = Array.new(26) { highlight }

      get "/api/v1/achievements/highlights/pending", headers: service_headers

      expect(json.fetch("data").pluck("id")).to eq(unlocks.first(25).map(&:id))
    end

    it "excludes departed members and bots" do
      departed = create(:user, server_left_at: 1.day.ago)
      highlight(user: departed, linked_account: create(:user_linked_account, user: departed))
      bot = create(:user, is_bot: true)
      highlight(user: bot, linked_account: create(:user_linked_account, user: bot))
      kept = highlight

      get "/api/v1/achievements/highlights/pending", headers: service_headers

      expect(json.fetch("data").pluck("id")).to eq([ kept.id ])
    end

    it "reports the PSN auth alert" do
      get "/api/v1/achievements/highlights/pending", headers: service_headers
      expect(json.fetch("alerts")).to eq("psn_auth_expired_at" => nil, "psn_auth_alerted" => false)

      AchievementHubState.set("psn_auth_expired_at", "2026-11-01T12:00:00Z")
      get "/api/v1/achievements/highlights/pending", headers: service_headers
      expect(json.fetch("alerts")).to eq("psn_auth_expired_at" => "2026-11-01T12:00:00Z", "psn_auth_alerted" => false)
    end
  end

  describe "POST /api/v1/achievements/highlights/ack" do
    def ack(cursor, headers: service_headers)
      post "/api/v1/achievements/highlights/ack", params: { cursor: cursor }, headers: headers, as: :json
    end

    it "stores the cursor, so acked Unlocks are not listed again" do
      posted = highlight
      later = highlight

      ack(posted.id)

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "cursor")).to eq(posted.id)
      get "/api/v1/achievements/highlights/pending", headers: service_headers
      expect(json.fetch("data").pluck("id")).to eq([ later.id ])
    end

    it "only moves forward: a stale ack is a no-op" do
      ack(500)
      ack(200)

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "cursor")).to eq(500)
      get "/api/v1/achievements/highlights/pending", headers: service_headers
      expect(json.dig("meta", "cursor")).to eq(500)
    end

    it "rejects a missing or malformed cursor" do
      ack("abc")
      expect(response).to have_http_status(:unprocessable_content)

      ack(-1)
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "is forbidden to admins and members" do
      ack(1, headers: auth_headers_for(create(:user, role_admin: true)))

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "POST /api/v1/achievements/alerts/ack" do
    def ack_alert(alert = "psn_auth_expired", headers: service_headers)
      post "/api/v1/achievements/alerts/ack", params: { alert: alert }, headers: headers, as: :json
    end

    def alerts
      get "/api/v1/achievements/highlights/pending", headers: service_headers
      json.fetch("alerts")
    end

    it "marks the current expiry as posted, once" do
      AchievementHubState.set("psn_auth_expired_at", "2026-11-01T12:00:00Z")

      ack_alert

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to eq("psn_auth_expired_at" => "2026-11-01T12:00:00Z", "psn_auth_alerted" => true)
      expect(alerts.fetch("psn_auth_alerted")).to be(true)
    end

    it "re-arms on a new expiry timestamp" do
      AchievementHubState.set("psn_auth_expired_at", "2026-11-01T12:00:00Z")
      ack_alert
      AchievementHubState.set("psn_auth_expired_at", "2026-11-08T06:00:00Z")

      expect(alerts).to eq("psn_auth_expired_at" => "2026-11-08T06:00:00Z", "psn_auth_alerted" => false)
    end

    it "is a no-op while PSN auth is healthy" do
      ack_alert

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to eq("psn_auth_expired_at" => nil, "psn_auth_alerted" => false)
    end

    it "rejects an unknown alert" do
      ack_alert("steam_down")

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "is forbidden to admins and members" do
      ack_alert(headers: auth_headers_for(create(:user, role_admin: true)))

      expect(response).to have_http_status(:forbidden)
    end
  end
end
