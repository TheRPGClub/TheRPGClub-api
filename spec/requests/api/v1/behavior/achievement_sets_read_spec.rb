# frozen_string_literal: true

require "rails_helper"

# Behavior specs for the Achievement Set page read (api-09): every Achievement
# in display order with the subject member's Unlock state and the viewer's own
# (`viewer_unlocked`, for spoiler blur), the member's progress and the GameDB
# link. Removed Achievements only appear when the member unlocked them, in a
# separate `removed_achievements` list.
RSpec.describe "api/v1 achievement set read behavior", type: :request do
  let(:viewer) { create(:user) }
  let(:member) { create(:user) }
  let(:game) { create(:game) }
  let(:set) { create(:achievement_set, provider: "retroachievements", game_id: game.game_id, title: "Set") }
  let(:account) { create(:user_linked_account, user: member, provider: "retroachievements") }
  let(:viewer_account) { create(:user_linked_account, user: viewer, provider: "retroachievements") }

  let!(:second) { create(:achievement, achievement_set: set, display_order: 2, hidden: true, points: 10) }
  let!(:first) { create(:achievement, achievement_set: set, display_order: 1, points: 5) }
  let!(:removed_unlocked) { create(:achievement, achievement_set: set, display_order: 3, removed_at: 1.day.ago) }
  let!(:removed_locked) { create(:achievement, achievement_set: set, display_order: 4, removed_at: 1.day.ago) }

  def unlock(acct, achievement, **attrs)
    create(:user_achievement_unlock, linked_account: acct, user: acct.user, achievement: achievement, **attrs)
  end

  it "returns the set, its Achievements in display order and the member's and viewer's Unlock state" do
    at = Time.utc(2026, 10, 1, 12)
    unlock(account, first, unlocked_at: at, hardcore: true)
    unlock(account, removed_unlocked, unlocked_at: at)
    unlock(viewer_account, second, unlocked_at: at)
    create(:user_achievement_set_progress, linked_account: account, user: member, achievement_set: set,
      earned_count: 1, total_count: 2, points_earned: 5)

    get "/api/v1/achievement_sets/#{set.id}", params: { user_id: member.user_id }, headers: auth_headers_for(viewer)

    expect(response).to have_http_status(:ok)
    data = json.fetch("data")
    expect(data).to include("id" => set.id, "title" => "Set", "game_id" => game.game_id, "provider" => "retroachievements")
    expect(data.fetch("game")).to include("game_id" => game.game_id)
    expect(data.fetch("user")).to include("user_id" => member.user_id)
    expect(data.fetch("progress")).to include("earned_count" => 1, "total_count" => 2, "points_earned" => 5)

    achievements = data.fetch("achievements")
    expect(achievements.map { |a| a.fetch("id") }).to eq([ first.id, second.id ])
    expect(achievements.first).to include("unlocked_at" => at.iso8601(3), "hardcore" => true, "viewer_unlocked" => false)
    # The viewer's state differs from the subject's: the viewer has the hidden one.
    expect(achievements.last).to include("unlocked_at" => nil, "hardcore" => false, "viewer_unlocked" => true,
      "hidden" => true)
    expect(data.fetch("removed_achievements").map { |a| a.fetch("id") }).to eq([ removed_unlocked.id ])
  end

  it "returns the bare set without a user_id" do
    get "/api/v1/achievement_sets/#{set.id}", headers: auth_headers_for(viewer)

    expect(response).to have_http_status(:ok)
    data = json.fetch("data")
    expect(data.fetch("user")).to be_nil
    expect(data.fetch("progress")).to be_nil
    expect(data.fetch("achievements").map { |a| a["unlocked_at"] }).to all(be_nil)
    expect(data.fetch("removed_achievements")).to be_empty
  end

  it "hides a placeholder progress row" do
    create(:user_achievement_set_progress, linked_account: account, user: member, achievement_set: set, synced_at: nil)

    get "/api/v1/achievement_sets/#{set.id}", params: { user_id: member.user_id }, headers: auth_headers_for(viewer)

    expect(json.dig("data", "progress")).to be_nil
  end

  it "is 404 for a departed member" do
    unlock(account, first)
    member.update!(server_left_at: 1.day.ago)

    get "/api/v1/achievement_sets/#{set.id}", params: { user_id: member.user_id }, headers: auth_headers_for(viewer)

    expect(response).to have_http_status(:not_found)
  end

  it "is 404 for an unknown set" do
    get "/api/v1/achievement_sets/0", headers: auth_headers_for(viewer)

    expect(response).to have_http_status(:not_found)
  end

  it "requires authentication" do
    get "/api/v1/achievement_sets/#{set.id}"

    expect(response).to have_http_status(:unauthorized)
  end
end
