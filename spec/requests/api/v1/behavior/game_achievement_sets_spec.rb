# frozen_string_literal: true

require "rails_helper"

# Behavior specs for a GameDB game's Achievement showcase (api-09): the sets
# linked to the game, the members who completed each, and the viewer's own
# progress for the "Your progress" bar.
RSpec.describe "api/v1 game achievement sets behavior", type: :request do
  let(:viewer) { create(:user) }
  let(:game) { create(:game) }
  let!(:psn_set) { create(:achievement_set, provider: "psn", game_id: game.game_id, title: "PS5", achievements_count: 40) }
  let!(:steam_set) { create(:achievement_set, provider: "steam", game_id: game.game_id, title: "PC", achievements_count: 30) }

  def progress(user, set, **attrs)
    account = UserLinkedAccount.find_by(user: user, provider: set.provider) ||
      create(:user_linked_account, user: user, provider: set.provider)
    create(:user_achievement_set_progress, linked_account: account, user: user, achievement_set: set, **attrs)
  end

  it "lists the game's sets with the members who completed each and the viewer's progress" do
    create(:achievement_set, provider: "steam") # another game's set
    first = create(:user)
    second = create(:user)
    progress(second, steam_set, earned_count: 30, total_count: 30, completed_at: Time.utc(2026, 9, 2))
    progress(first, steam_set, earned_count: 30, total_count: 30, completed_at: Time.utc(2026, 9, 1))
    progress(create(:user, server_left_at: 1.day.ago), steam_set, earned_count: 30, total_count: 30, completed_at: 1.day.ago)
    progress(create(:user), steam_set, earned_count: 30, total_count: 30, completed_at: 1.day.ago, synced_at: nil)
    progress(create(:user), steam_set, earned_count: 3, total_count: 30)
    mine = progress(viewer, psn_set, earned_count: 10, total_count: 40)

    get "/api/v1/games/#{game.game_id}/achievement_sets", headers: auth_headers_for(viewer)

    expect(response).to have_http_status(:ok)
    data = json.fetch("data")
    expect(data.map { |s| s.fetch("id") }).to eq([ psn_set.id, steam_set.id ])
    psn, steam = data
    expect(psn).to include("provider" => "psn", "achievements_count" => 40, "game_id" => game.game_id, "completions" => [])
    expect(psn.fetch("viewer_progress")).to include("id" => mine.id, "earned_count" => 10, "total_count" => 40)
    expect(steam.fetch("viewer_progress")).to be_nil
    expect(steam.fetch("completions").map { |c| [ c.dig("user", "user_id"), c.fetch("completed_at") ] }).to eq([
      [ first.user_id, "2026-09-01T00:00:00.000Z" ],
      [ second.user_id, "2026-09-02T00:00:00.000Z" ]
    ])
  end

  def unlock(user, achievement)
    account = UserLinkedAccount.find_by(user: user, provider: achievement.achievement_set.provider) ||
      create(:user_linked_account, user: user, provider: achievement.achievement_set.provider)
    create(:user_achievement_unlock, linked_account: account, user: user, achievement: achievement)
  end

  def game_sets
    get "/api/v1/games/#{game.game_id}/achievement_sets", headers: auth_headers_for(viewer)
    expect(response).to have_http_status(:ok)
    json.fetch("data")
  end

  it "lists each set's Achievements in display order with their holders and the viewer's Unlock" do
    second = create(:achievement, achievement_set: steam_set, display_order: 2, name: "Second", rarity: 12.5)
    secret = create(:achievement, achievement_set: steam_set, display_order: 1, name: "Secret", description: "Spoiler",
      hidden: true, rarity: nil)
    create(:achievement, achievement_set: steam_set, display_order: 0, removed_at: 1.day.ago)
    trophy = create(:achievement, achievement_set: psn_set, display_order: 1, tier: "gold")
    holder = create(:user)
    unlock(holder, second)
    unlock(viewer, second)
    unlock(create(:user, server_left_at: 1.day.ago), second)
    unlock(holder, trophy)

    psn, steam = game_sets

    expect(steam.fetch("achievements")).to eq([
      {
        "id" => secret.id, "name" => "Secret", "description" => "Spoiler",
        "icon_url" => secret.icon_url, "icon_locked_url" => secret.icon_locked_url,
        "hidden" => true, "tier" => nil, "points" => secret.points, "rarity" => nil,
        "holders" => [], "viewer_unlocked" => false
      },
      {
        "id" => second.id, "name" => "Second", "description" => second.description,
        "icon_url" => second.icon_url, "icon_locked_url" => second.icon_locked_url,
        "hidden" => false, "tier" => nil, "points" => second.points, "rarity" => 12.5,
        "holders" => [ holder.user_id, viewer.user_id ], "viewer_unlocked" => true
      }
    ])
    expect(psn.fetch("achievements")).to contain_exactly(
      include("id" => trophy.id, "tier" => "gold", "holders" => [ holder.user_id ], "viewer_unlocked" => false)
    )
  end

  it "reads every set's Achievements in a fixed number of queries" do
    headers = auth_headers_for(viewer)
    count_queries = lambda do
      queries = 0
      subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
        # Cached hits count too, so the query cache cannot mask a per-set query.
        queries += 1 unless payload[:name] == "SCHEMA"
      end
      begin
        get "/api/v1/games/#{game.game_id}/achievement_sets", headers: headers
      ensure
        ActiveSupport::Notifications.unsubscribe(subscriber)
      end
      expect(response).to have_http_status(:ok)
      queries
    end

    unlock(create(:user), create(:achievement, achievement_set: steam_set))
    small = count_queries.call

    3.times do
      set = create(:achievement_set, provider: "retroachievements", game_id: game.game_id)
      2.times { unlock(create(:user), create(:achievement, achievement_set: set)) }
    end
    unlock(viewer, create(:achievement, achievement_set: psn_set))
    large = count_queries.call

    expect(large).to eq(small)
  end

  it "is an empty list for a game without sets" do
    get "/api/v1/games/#{create(:game).game_id}/achievement_sets", headers: auth_headers_for(viewer)

    expect(response).to have_http_status(:ok)
    expect(json.fetch("data")).to eq([])
  end

  it "is 404 for an unknown game" do
    get "/api/v1/games/0/achievement_sets", headers: auth_headers_for(viewer)

    expect(response).to have_http_status(:not_found)
  end

  it "requires authentication" do
    get "/api/v1/games/#{game.game_id}/achievement_sets"

    expect(response).to have_http_status(:unauthorized)
  end
end
