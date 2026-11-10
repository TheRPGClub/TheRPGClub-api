# frozen_string_literal: true

require "rails_helper"

# Behavior specs for the bot's Highlight endpoints: the pending list of
# unannounced Highlights, the per-Unlock ack and the PSN auth alert ack.
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
                                 "tier" => "platinum", "rarity" => 12.3, "hidden" => false),
        "achievement_set" => include("id" => set.id, "title" => "Elden Ring", "provider" => "psn")
      )
    end

    it "dates a Mastery by its hardcore time" do
      mastered_at = Time.utc(2026, 10, 30, 12)
      highlight(highlight: "mastery", hardcore: true, unlocked_at: Time.utc(2024, 1, 1), hardcore_unlocked_at: mastered_at)

      get "/api/v1/achievements/highlights/pending", headers: service_headers

      expect(Time.iso8601(json.fetch("data").sole.fetch("unlocked_at"))).to eq(mastered_at)
    end

    it "flags a hidden Achievement, so the bot can mask its name and description" do
      hidden = highlight
      hidden.achievement.update!(hidden: true)

      get "/api/v1/achievements/highlights/pending", headers: service_headers

      expect(json.fetch("data").sole.dig("achievement", "hidden")).to be(true)
    end

    it "holds every Highlight while the Achievement Hub is Off, and lists it once it is back on" do
      unlock = highlight
      set_feature_flag("achievement_hub", "off")

      get "/api/v1/achievements/highlights/pending", headers: service_headers
      expect(json.fetch("data")).to eq([])

      set_feature_flag("achievement_hub", "preview")
      get "/api/v1/achievements/highlights/pending", headers: service_headers
      expect(json.fetch("data").map { |row| row.fetch("id") }).to eq([ unlock.id ])
    end

    it "is forbidden to admins and members" do
      get "/api/v1/achievements/highlights/pending", headers: auth_headers_for(create(:user, role_admin: true))

      expect(response).to have_http_status(:forbidden)
    end

    it "lists only Unlocks not yet announced, oldest first" do
      highlight(announced_at: 1.hour.ago)
      first = highlight
      second = highlight

      get "/api/v1/achievements/highlights/pending", headers: service_headers

      expect(json.fetch("data").pluck("id")).to eq([ first.id, second.id ])
      expect(json).not_to have_key("meta")
    end

    # Ids are assigned at INSERT but seen at COMMIT, and the three Provider
    # chains sync concurrently: an older Unlock can appear after a newer one
    # was acked, and must still be listed.
    it "still lists an older Unlock that appears after a newer one was acked" do
      older = highlight(announceable: false)
      newer = highlight
      post "/api/v1/achievements/highlights/ack", params: { data: { ids: [ newer.id ] } }, headers: service_headers,
        as: :json
      older.update!(announceable: true)

      get "/api/v1/achievements/highlights/pending", headers: service_headers

      expect(json.fetch("data").pluck("id")).to eq([ older.id ])
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

    it "excludes removed Achievements" do
      highlight.achievement.update!(removed_at: 1.hour.ago)
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
    def ack(ids, headers: service_headers)
      post "/api/v1/achievements/highlights/ack", params: { data: { ids: ids } }, headers: headers, as: :json
    end

    def pending_ids
      get "/api/v1/achievements/highlights/pending", headers: service_headers
      json.fetch("data").pluck("id")
    end

    it "marks the acked Unlocks announced, so they are not listed again" do
      posted = highlight
      skipped = highlight
      later = highlight

      ack([ posted.id, skipped.id ])

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "ids")).to contain_exactly(posted.id, skipped.id)
      expect(posted.reload.announced_at).to be_present
      expect(pending_ids).to eq([ later.id ])
    end

    it "is idempotent, keeping the first announcement time" do
      posted = highlight
      ack([ posted.id ])
      first_at = posted.reload.announced_at

      ack([ posted.id ])

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "ids")).to eq([ posted.id ])
      expect(posted.reload.announced_at).to eq(first_at)
    end

    it "ignores ids that are not announceable" do
      quiet = highlight(announceable: false)

      ack([ quiet.id, 999_999_999 ])

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "ids")).to eq([])
      expect(quiet.reload.announced_at).to be_nil
    end

    it "rejects missing or malformed ids" do
      post "/api/v1/achievements/highlights/ack", params: { data: {} }, headers: service_headers, as: :json
      expect(response).to have_http_status(:unprocessable_content)

      ack("1")
      expect(response).to have_http_status(:unprocessable_content)

      ack([ "abc" ])
      expect(response).to have_http_status(:unprocessable_content)

      ack([ -1 ])
      expect(response).to have_http_status(:unprocessable_content)

      ack(Array.new(101) { |index| index + 1 })
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "is forbidden to admins and members" do
      ack([ 1 ], headers: auth_headers_for(create(:user, role_admin: true)))

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
