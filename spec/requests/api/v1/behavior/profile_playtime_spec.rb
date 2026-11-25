# frozen_string_literal: true

require "rails_helper"

# Playtime on the profile and the shelves (spec api#457, ticket api#460): the
# profile's total and per-shelf totals, each shelf item's `playtime_minutes`,
# Now Playing's `playthrough_minutes`, and `sort=most_played`.
RSpec.describe "api/v1 profile playtime behavior", type: :request do
  let(:member) { create(:user) }
  let(:viewer) { create(:user) }
  let(:headers) { auth_headers_for(viewer) }

  def playtime(game, minutes, user: member) = create(:manual_playtime, user: user, game: game, platform: nil,
    minutes: minutes)

  describe "GET /users/:user_id" do
    it "gives the total and each shelf's total, counting a game on a shelf once" do
      zelda = create(:game, title: "Zelda")
      metroid = create(:game, title: "Metroid")
      kirby = create(:game, title: "Kirby")
      unshelved = create(:game, title: "Unshelved")
      playtime(zelda, 600)
      playtime(metroid, 120)
      playtime(unshelved, 30)
      playtime(zelda, 999, user: viewer)

      create(:completion, user: member, game: zelda)
      create(:completion, user: member, game: zelda, completion_type: "Main Story", completed_at: 1.year.ago)
      create(:completion, user: member, game: kirby)
      create(:backlog_entry, user: member, game: metroid)
      create(:favorite, user: member, game: zelda)
      create(:collection_entry, user: member, game: zelda, platform: create(:platform))
      create(:collection_entry, user: member, game: zelda, platform: create(:platform))
      create(:collection_entry, user: member, game: metroid)
      create(:now_playing_entry, user: member, game: metroid)

      get "/api/v1/users/#{member.user_id}", headers: headers

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "playtime")).to eq(
        "total_minutes" => 750,
        "shelves" => { "completed" => 600, "backlog" => 120, "favorites" => 600, "collection" => 720,
                       "now_playing" => 120 }
      )
    end

    it "is zero everywhere for a member with no Playtime" do
      create(:completion, user: member)

      get "/api/v1/users/#{member.user_id}", headers: headers

      expect(json.dig("data", "playtime")).to eq(
        "total_minutes" => 0,
        "shelves" => { "completed" => 0, "backlog" => 0, "favorites" => 0, "collection" => 0, "now_playing" => 0 }
      )
    end

    it "leaves out the shelf totals of Features the viewer cannot use, as with counts" do
      set_feature_flag("game_completions", "off")
      set_feature_flag("collection", "off")

      get "/api/v1/users/#{member.user_id}", headers: headers

      expect(json.dig("data", "playtime", "shelves").keys).to contain_exactly("backlog", "favorites", "now_playing")
    end
  end

  describe "shelf lists" do
    let(:playtime_tables) { /user_game_manual_playtimes|user_achievement_set_progress|user_game_playthroughs/ }
    let(:zelda) { create(:game, title: "Zelda") }
    let(:kirby) { create(:game, title: "Kirby") }

    before do
      playtime(zelda, 600)
      playtime(kirby, 999, user: viewer)
    end

    {
      "now_playing" => :now_playing_entry, "completions" => :completion, "backlog" => :backlog_entry,
      "favorites" => :favorite, "collections" => :collection_entry
    }.each do |list, factory|
      it "gives each #{list} item the member's playtime_minutes, 0 for a game with none" do
        create(factory, user: member, game: zelda)
        create(factory, user: member, game: kirby)

        get "/api/v1/users/#{member.user_id}/#{list}", headers: headers

        expect(response).to have_http_status(:ok)
        minutes = json.fetch("data").to_h { |item| [ item.fetch("gamedb_game_id"), item.fetch("playtime_minutes") ] }
        expect(minutes).to eq(zelda.game_id => 600, kirby.game_id => 0)
      end
    end

    it "gives Now Playing items the open Playthrough's time, null when none is open" do
      create(:now_playing_entry, user: member, game: zelda)
      create(:now_playing_entry, user: member, game: kirby)
      create(:playthrough, user: member, game: zelda, baseline_minutes: 450)

      get "/api/v1/users/#{member.user_id}/now_playing", headers: headers

      items = json.fetch("data").index_by { |item| item.fetch("gamedb_game_id") }
      expect(items.fetch(zelda.game_id)).to include("playtime_minutes" => 600, "playthrough_minutes" => 150)
      expect(items.fetch(kirby.game_id)).to include("playtime_minutes" => 0, "playthrough_minutes" => nil)
    end

    it "gives null for a Now Playing entry with no game" do
      create(:now_playing_entry, user: member, game: nil)

      get "/api/v1/users/#{member.user_id}/now_playing", headers: headers

      expect(json.fetch("data")).to contain_exactly(include("gamedb_game_id" => nil, "playtime_minutes" => nil,
        "playthrough_minutes" => nil))
    end

    it "reads Playtime in the same number of queries however many items the page has" do
      queries_for = lambda do |count|
        create_list(:completion, count, user: member).each { |completion| playtime(completion.game, 60) }
        queries = 0
        subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
          queries += 1 if payload[:sql].match?(playtime_tables)
        end
        begin
          get "/api/v1/users/#{member.user_id}/completions", headers: headers
        ensure
          ActiveSupport::Notifications.unsubscribe(subscriber)
        end
        queries
      end

      one = queries_for.call(1)
      expect(queries_for.call(5)).to eq(one)
    end
  end

  describe "sort=most_played" do
    it "orders each list by the member's Playtime, then title, across pages" do
      { "Bravo" => 60, "Alpha" => 60, "Delta" => 0, "Charlie" => 300, "Echo" => nil }.each do |title, minutes|
        game = create(:game, title: title)
        playtime(game, minutes) if minutes
        playtime(game, 5000, user: viewer)
        create(:backlog_entry, user: member, game: game)
      end

      titles = [ 1, 2, 3 ].flat_map do |page|
        get "/api/v1/users/#{member.user_id}/backlog", params: { sort: "most_played", per: 2, page: page },
          headers: headers
        json.fetch("data").map { |item| item.dig("game", "title") }
      end

      expect(titles).to eq(%w[Charlie Alpha Bravo Delta Echo])
      expect(json.dig("meta", "count")).to eq(5)
    end

    {
      "now_playing" => :now_playing_entry, "completions" => :completion, "favorites" => :favorite,
      "collections" => :collection_entry
    }.each do |list, factory|
      it "sorts #{list} and keeps playtime_minutes on each item" do
        short = create(:game, title: "Short")
        long = create(:game, title: "Long")
        playtime(short, 10)
        playtime(long, 900)
        create(factory, user: member, game: short)
        create(factory, user: member, game: long)

        get "/api/v1/users/#{member.user_id}/#{list}", params: { sort: "most_played" }, headers: headers

        expect(json.fetch("data").map { |item| [ item.dig("game", "title"), item["playtime_minutes"] ] })
          .to eq([ [ "Long", 900 ], [ "Short", 10 ] ])
      end
    end

    it "falls back to title when the member has no Playtime" do
      %w[Beta Alpha].each { |title| create(:favorite, user: member, game: create(:game, title: title)) }

      get "/api/v1/users/#{member.user_id}/favorites", params: { sort: "most_played" }, headers: headers

      expect(json.fetch("data").map { |item| [ item.dig("game", "title"), item["playtime_minutes"] ] })
        .to eq([ [ "Alpha", 0 ], [ "Beta", 0 ] ])
    end

    it "is 422 invalid_sort for an unknown sort" do
      get "/api/v1/users/#{member.user_id}/favorites", params: { sort: "loudest" }, headers: headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("error")).to eq("invalid_sort")
    end
  end
end
