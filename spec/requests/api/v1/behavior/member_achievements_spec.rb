# frozen_string_literal: true

require "rails_helper"

# Behavior specs for a member's Achievement Hub reads (api-09): the summary
# header, the set progress grid and the flat Unlocks list. Any signed-in member
# may read them. Departed members, placeholder progress rows and removed
# Achievements stay out of every read.
RSpec.describe "api/v1 member achievements behavior", type: :request do
  let(:viewer) { create(:user) }
  let(:member) { create(:user) }

  def link(user, provider, display_name: "name_#{provider}")
    create(:user_linked_account, user: user, provider: provider, display_name: display_name)
  end

  def progress(account, set, **attrs)
    create(:user_achievement_set_progress, linked_account: account, user: account.user, achievement_set: set, **attrs)
  end

  def unlock(account, achievement, **attrs)
    create(:user_achievement_unlock, linked_account: account, user: account.user, achievement: achievement, **attrs)
  end

  describe "GET /api/v1/users/:user_id/achievements/summary" do
    it "totals per Provider and overall, lists Linked Accounts and the 5 latest Unlocks" do
      steam = link(member, "steam", display_name: "SteamName")
      ra = link(member, "retroachievements", display_name: "RAName")
      steam_set = create(:achievement_set, provider: "steam")
      ra_set = create(:achievement_set, provider: "retroachievements")
      progress(steam, steam_set, earned_count: 10, total_count: 10, points_earned: 0, completed_at: 1.day.ago)
      progress(ra, ra_set, earned_count: 4, total_count: 8, points_earned: 50)
      progress(ra, create(:achievement_set, provider: "retroachievements"),
        earned_count: 2, total_count: 2, points_earned: 25, completed_at: 2.days.ago, mastered_at: 2.days.ago)
      # A placeholder row (never imported) counts for nothing.
      progress(ra, create(:achievement_set, provider: "retroachievements"), earned_count: 99, synced_at: nil)
      unlocks = Array.new(6) { |i| unlock(steam, create(:achievement, achievement_set: steam_set), unlocked_at: i.hours.ago) }
      removed = create(:achievement, achievement_set: steam_set, removed_at: 1.day.ago)
      unlock(steam, removed, unlocked_at: 1.minute.from_now)

      get "/api/v1/users/#{member.user_id}/achievements/summary", headers: auth_headers_for(viewer)

      expect(response).to have_http_status(:ok)
      data = json.fetch("data")
      expect(data.fetch("user")).to include("user_id" => member.user_id)
      expect(data.fetch("totals")).to eq(
        "unlocks" => 16, "completions" => 2, "masteries" => 1, "platinums" => 0, "points" => 75
      )
      expect(data.fetch("providers")).to contain_exactly(
        { "provider" => "retroachievements", "unlocks" => 6, "completions" => 1, "masteries" => 1, "platinums" => 0, "points" => 75 },
        { "provider" => "steam", "unlocks" => 10, "completions" => 1, "masteries" => 0, "platinums" => 0, "points" => 0 }
      )
      expect(data.fetch("linked_accounts")).to contain_exactly(
        { "provider" => "steam", "display_name" => "SteamName" },
        { "provider" => "retroachievements", "display_name" => "RAName" }
      )
      latest = data.fetch("latest_unlocks")
      expect(latest.map { |u| u.fetch("id") }).to eq(unlocks.first(5).map(&:id))
      expect(latest.first.dig("achievement", "id")).to eq(unlocks.first.achievement_id)
      expect(latest.first.dig("achievement_set", "id")).to eq(steam_set.id)
    end

    it "lists the 4 rarest Unlocks, rarest first, leaving out removed Achievements" do
      steam = link(member, "steam")
      set = create(:achievement_set, provider: "steam")
      common = unlock(steam, create(:achievement, achievement_set: set, rarity: 80.5))
      rarest = unlock(steam, create(:achievement, achievement_set: set, rarity: 0.4))
      unlock(steam, create(:achievement, achievement_set: set, rarity: 99))
      rare = unlock(steam, create(:achievement, achievement_set: set, rarity: 3.2))
      uncommon = unlock(steam, create(:achievement, achievement_set: set, rarity: 40))
      unlock(steam, create(:achievement, achievement_set: set, rarity: 0.1, removed_at: 1.day.ago))
      unlock(link(viewer, "steam"), create(:achievement, achievement_set: set, rarity: 0.2))

      get "/api/v1/users/#{member.user_id}/achievements/summary", headers: auth_headers_for(viewer)

      expect(response).to have_http_status(:ok)
      rarest_unlocks = json.dig("data", "rarest_unlocks")
      expect(rarest_unlocks.map { |u| u.fetch("id") }).to eq([ rarest.id, rare.id, uncommon.id, common.id ])
      expect(rarest_unlocks.first.dig("achievement", "rarity")).to eq(0.4)
      expect(rarest_unlocks.first.dig("achievement_set", "id")).to eq(set.id)
    end

    it "ranks Unlocks with no known Rarity after every rated one" do
      steam = link(member, "steam")
      set = create(:achievement_set, provider: "steam")
      unrated = unlock(steam, create(:achievement, achievement_set: set, rarity: nil), unlocked_at: 1.hour.ago)
      rated = unlock(steam, create(:achievement, achievement_set: set, rarity: 95), unlocked_at: 2.hours.ago)

      get "/api/v1/users/#{member.user_id}/achievements/summary", headers: auth_headers_for(viewer)

      expect(json.dig("data", "rarest_unlocks").map { |u| u.fetch("id") }).to eq([ rated.id, unrated.id ])
    end

    it "lists a linked Provider with nothing synced yet as zero totals" do
      link(member, "psn")

      get "/api/v1/users/#{member.user_id}/achievements/summary", headers: auth_headers_for(viewer)

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "providers")).to eq([
        { "provider" => "psn", "unlocks" => 0, "completions" => 0, "masteries" => 0, "platinums" => 0, "points" => 0 }
      ])
      expect(json.dig("data", "totals", "unlocks")).to eq(0)
    end

    it "is 404 for a member with no Linked Account" do
      get "/api/v1/users/#{member.user_id}/achievements/summary", headers: auth_headers_for(viewer)

      expect(response).to have_http_status(:not_found)
    end

    it "is 404 for a departed member" do
      link(member, "steam")
      member.update!(server_left_at: 1.day.ago)

      get "/api/v1/users/#{member.user_id}/achievements/summary", headers: auth_headers_for(viewer)

      expect(response).to have_http_status(:not_found)
    end

    it "requires authentication" do
      get "/api/v1/users/#{member.user_id}/achievements/summary"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/users/:user_id/achievements/sets" do
    let(:steam) { link(member, "steam") }
    let(:psn) { link(member, "psn") }
    let!(:done) do
      progress(steam, create(:achievement_set, provider: "steam", title: "Beta"),
        earned_count: 5, total_count: 5, completed_at: 3.days.ago, last_unlocked_at: 3.days.ago)
    end
    let!(:half) do
      progress(psn, create(:achievement_set, provider: "psn", title: "alpha"),
        earned_count: 5, total_count: 10, last_unlocked_at: 1.day.ago)
    end
    let!(:little) do
      progress(steam, create(:achievement_set, provider: "steam", title: "Gamma"),
        earned_count: 1, total_count: 10, last_unlocked_at: 2.days.ago)
    end
    let!(:untouched) do
      progress(steam, create(:achievement_set, provider: "steam", title: "Delta"), earned_count: 0, total_count: 4)
    end

    def ids
      json.fetch("data").map { |row| row.fetch("id") }
    end

    it "lists the member's set progress, most recent Unlock first, with the set embedded" do
      progress(steam, create(:achievement_set), earned_count: 3, synced_at: nil)
      progress(link(viewer, "steam"), create(:achievement_set), earned_count: 1, last_unlocked_at: Time.current)

      get "/api/v1/users/#{member.user_id}/achievements/sets", headers: auth_headers_for(viewer)

      expect(response).to have_http_status(:ok)
      expect(ids).to eq([ half.id, little.id, done.id, untouched.id ])
      expect(json.fetch("data").first).to include(
        "provider" => "psn", "earned_count" => 5, "total_count" => 10, "completed_at" => nil
      )
      expect(json.fetch("data").first.fetch("achievement_set")).to include(
        "id" => half.achievement_set_id, "title" => "alpha", "provider" => "psn"
      )
      expect(json.fetch("meta")).to include("count" => 4, "page" => 1)
    end

    it "filters by Provider and status" do
      get "/api/v1/users/#{member.user_id}/achievements/sets", params: { provider: "steam", status: "in_progress" },
        headers: auth_headers_for(viewer)
      expect(ids).to eq([ little.id ])

      get "/api/v1/users/#{member.user_id}/achievements/sets", params: { status: "completed" },
        headers: auth_headers_for(viewer)
      expect(ids).to eq([ done.id ])
    end

    it "sorts by progress and by title" do
      get "/api/v1/users/#{member.user_id}/achievements/sets", params: { sort: "progress" }, headers: auth_headers_for(viewer)
      expect(ids).to eq([ done.id, half.id, little.id, untouched.id ])

      get "/api/v1/users/#{member.user_id}/achievements/sets", params: { sort: "title" }, headers: auth_headers_for(viewer)
      expect(ids).to eq([ half.id, done.id, untouched.id, little.id ])
    end

    it "paginates" do
      get "/api/v1/users/#{member.user_id}/achievements/sets", params: { per: 3, page: 2 }, headers: auth_headers_for(viewer)

      expect(ids).to eq([ untouched.id ])
      expect(json.fetch("meta")).to include("count" => 4, "pages" => 2, "page" => 2)
    end

    it "rejects an unknown status, sort or Provider" do
      %w[status sort provider].each do |name|
        get "/api/v1/users/#{member.user_id}/achievements/sets", params: { name => "bogus" }, headers: auth_headers_for(viewer)
        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    it "excludes a departed member" do
      member.update!(server_left_at: 1.day.ago)

      get "/api/v1/users/#{member.user_id}/achievements/sets", headers: auth_headers_for(viewer)

      expect(response).to have_http_status(:ok)
      expect(ids).to be_empty
    end
  end

  describe "GET /api/v1/users/:user_id/achievements/unlocks" do
    let(:steam) { link(member, "steam") }
    let(:set) { create(:achievement_set, provider: "steam") }

    it "lists the member's Unlocks newest first, paginated, with viewer_unlocked for the viewer" do
      hidden = create(:achievement, achievement_set: set, hidden: true)
      older = unlock(steam, create(:achievement, achievement_set: set), unlocked_at: 2.days.ago)
      newer = unlock(steam, hidden, unlocked_at: 1.day.ago, hardcore: true, highlight: "rare")
      unlock(steam, create(:achievement, achievement_set: set, removed_at: 1.hour.ago), unlocked_at: 1.hour.ago)
      unlock(link(viewer, "steam"), hidden, unlocked_at: 1.day.ago)

      get "/api/v1/users/#{member.user_id}/achievements/unlocks", headers: auth_headers_for(viewer)

      expect(response).to have_http_status(:ok)
      data = json.fetch("data")
      expect(data.map { |u| u.fetch("id") }).to eq([ newer.id, older.id ])
      expect(data.first).to include("hardcore" => true, "highlight" => "rare", "viewer_unlocked" => true,
        "user_id" => member.user_id)
      expect(data.first.fetch("achievement")).to include("id" => hidden.id, "hidden" => true, "rarity" => 50.0)
      expect(data.first.fetch("achievement_set")).to include("id" => set.id)
      expect(data.last.fetch("viewer_unlocked")).to be(false)
      expect(json.fetch("meta")).to include("count" => 2)

      get "/api/v1/users/#{member.user_id}/achievements/unlocks", params: { per: 1, page: 2 }, headers: auth_headers_for(viewer)
      expect(json.fetch("data").map { |u| u.fetch("id") }).to eq([ older.id ])
    end

    it "excludes a departed member" do
      unlock(steam, create(:achievement, achievement_set: set))
      member.update!(server_left_at: 1.day.ago)

      get "/api/v1/users/#{member.user_id}/achievements/unlocks", headers: auth_headers_for(viewer)

      expect(json.fetch("data")).to be_empty
    end
  end
end
