# frozen_string_literal: true

require "rails_helper"

# Behavior specs for GET /api/v1/users/:user_id/backlog/pick (the bot's
# `/backlog pick`, web-parity #286): a uniform, seed-deterministic suggestion of
# what to play next from the owner's backlog and/or collection.
RSpec.describe "api/v1/backlog pick behavior", type: :request do
  let(:owner) { create(:user) }
  let(:path) { "/api/v1/users/#{owner.user_id}/backlog/pick" }

  def pick(**params)
    get path, params: params, headers: auth_headers_for(owner)
    expect(response).to have_http_status(:ok)
    json
  end

  it "picks the owner's backlog entry with its game and HLTB times" do
    game = create(:game)
    entry = create(:backlog_entry, user: owner, game: game, note: "soon")
    RpgClubHltbCache.create!(gamedb_game_id: game.game_id, main: "12 Hours", main_sides: "20 Hours")

    body = pick(seed: 7)

    expect(body.fetch("data")).to include(
      "kind" => "backlog",
      "entry_id" => entry.entry_id,
      "gamedb_game_id" => game.game_id,
      "note" => "soon",
      "hours" => 12.0
    )
    expect(body.dig("data", "game")).to include("game_id" => game.game_id, "title" => game.title)
    expect(body.dig("data", "hltb")).to include("main" => "12 Hours", "main_sides" => "20 Hours")
    expect(body.fetch("meta")).to include(
      "seed" => 7, "position" => 0, "next_position" => 1, "total" => 1, "wrapped" => false
    )
  end

  describe "determinism" do
    before { create_list(:backlog_entry, 6, user: owner) }

    it "gives the same pick for the same seed and position" do
      first = pick(seed: 42, position: 3)
      second = pick(seed: 42, position: 3)

      expect(second.dig("data", "entry_id")).to eq(first.dig("data", "entry_id"))
      expect(second.fetch("meta")).to include("seed" => 42, "position" => 3, "next_position" => 4)
    end

    it "visits every candidate once when rerolling through next_position, then wraps" do
      position = 0
      picks = Array.new(6) do
        body = pick(seed: 99, position: position)
        position = body.dig("meta", "next_position")
        body.dig("data", "entry_id")
      end

      expect(picks).to match_array(UserGameBacklog.where(user_id: owner.user_id).pluck(:entry_id))
      wrapped = pick(seed: 99, position: position)
      expect(wrapped.fetch("meta")).to include("position" => 0, "wrapped" => true)
      expect(wrapped.dig("data", "entry_id")).to eq(picks.first)
    end

    it "draws a seed when none is given and returns it" do
      body = pick

      seed = body.dig("meta", "seed")
      expect(seed).to be_between(0, 0xffffffff)
      expect(pick(seed: seed).dig("data", "entry_id")).to eq(body.dig("data", "entry_id"))
    end
  end

  describe "sources and exclusions" do
    let(:backlog_game) { create(:game) }
    let(:collection_game) { create(:game) }

    before do
      create(:backlog_entry, user: owner, game: backlog_game)
      create(:collection_entry, user: owner, game: collection_game)
      create(:backlog_entry, game: create(:game)) # another member's backlog
    end

    it "uses only the backlog by default" do
      body = pick(seed: 1)

      expect(body.dig("data", "gamedb_game_id")).to eq(backlog_game.game_id)
      expect(body.dig("meta", "total")).to eq(1)
    end

    it "uses only the collection with source=collection" do
      body = pick(seed: 1, source: "collection")

      expect(body.fetch("data")).to include("kind" => "collection", "gamedb_game_id" => collection_game.game_id)
      expect(body.dig("meta", "total")).to eq(1)
    end

    it "uses both with source=both, counting a game in both lists once as its backlog entry" do
      create(:collection_entry, user: owner, game: backlog_game)

      kinds = (0..1).map { |position| pick(seed: 5, source: "both", position:).dig("data", "kind") }

      expect(pick(seed: 5, source: "both").dig("meta", "total")).to eq(2)
      expect(kinds).to contain_exactly("backlog", "collection")
    end

    it "skips games already on Now Playing" do
      create(:now_playing_entry, user: owner, game: backlog_game)

      body = pick(seed: 1, source: "both")

      expect(body.dig("data", "gamedb_game_id")).to eq(collection_game.game_id)
      expect(body.dig("meta", "total")).to eq(1)
    end
  end

  describe "platform_id filter" do
    let(:switch) { create(:platform, platform_name: "Switch") }
    let(:pc) { create(:platform, platform_name: "PC") }

    before do
      create(:backlog_entry, user: owner, platform: switch)
      create(:backlog_entry, user: owner, platform: switch)
      @pc_entry = create(:backlog_entry, user: owner, platform: pc)
      create(:backlog_entry, user: owner, platform: nil)
    end

    it "keeps only entries on exactly that platform" do
      body = pick(seed: 3, platform_id: pc.platform_id)

      expect(body.dig("data", "entry_id")).to eq(@pc_entry.entry_id)
      expect(body.dig("data", "platform")).to include("platform_id" => pc.platform_id, "platform_name" => "PC")
      expect(body.dig("meta", "total")).to eq(1)
    end

    it "lists the platform options, unfiltered, in meta.platforms" do
      body = pick(seed: 3, platform_id: pc.platform_id)

      expect(body.dig("meta", "platforms")).to eq([
        { "platform_id" => switch.platform_id, "platform_name" => "Switch", "platform_abbreviation" => nil, "count" => 2 },
        { "platform_id" => pc.platform_id, "platform_name" => "PC", "platform_abbreviation" => nil, "count" => 1 }
      ])
    end
  end

  describe "max_hours filter" do
    it "picks only games whose HLTB time fits, skipping games with no HLTB time" do
      short = create(:game)
      long = create(:game)
      create(:backlog_entry, user: owner, game: short)
      create(:backlog_entry, user: owner, game: long)
      create(:backlog_entry, user: owner) # no HLTB row
      RpgClubHltbCache.create!(gamedb_game_id: short.game_id, main: "--", single_player: "8½ Hours")
      RpgClubHltbCache.create!(gamedb_game_id: long.game_id, main: "60 Hours")

      ids = (0..2).map { |position| pick(seed: 11, max_hours: 10, position:).dig("data", "gamedb_game_id") }

      expect(ids.uniq).to eq([ short.game_id ])
      expect(pick(seed: 11, max_hours: 10).dig("data", "hours")).to eq(8.5)
    end

    it "reads minutes as fractions of an hour" do
      game = create(:game)
      create(:backlog_entry, user: owner, game: game)
      RpgClubHltbCache.create!(gamedb_game_id: game.game_id, main: "45 Mins")

      expect(pick(seed: 1, max_hours: 1).dig("data", "hours")).to eq(0.75)
    end

    it "returns no pick when nothing has a short enough time" do
      game = create(:game)
      create(:backlog_entry, user: owner, game: game)
      RpgClubHltbCache.create!(gamedb_game_id: game.game_id, main: "60 Hours")

      body = pick(seed: 1, max_hours: 10)

      expect(body.fetch("data")).to be_nil
      expect(body.fetch("meta")).to include("total" => 1, "position" => nil, "next_position" => nil)
    end
  end

  it "returns null data with an empty backlog" do
    body = pick(seed: 1)

    expect(body.fetch("data")).to be_nil
    expect(body.fetch("meta")).to include(
      "seed" => 1, "total" => 0, "position" => nil, "next_position" => nil, "wrapped" => false, "platforms" => []
    )
  end

  describe "access and params" do
    it "lets the service token pick for a member" do
      get path, params: { seed: 1 }, headers: service_headers

      expect(response).to have_http_status(:ok)
    end

    it "forbids another member" do
      get path, params: { seed: 1 }, headers: auth_headers_for(create(:user))

      expect(response).to have_http_status(:forbidden)
    end

    it "requires authentication" do
      get path

      expect(response).to have_http_status(:unauthorized)
    end

    [
      { source: "wishlist" }, { max_hours: 0 }, { max_hours: "abc" }, { seed: -1 },
      { seed: 0x1_0000_0000 }, { position: -1 }, { platform_id: "x" }
    ].each do |bad|
      it "422s invalid_#{bad.keys.first} for #{bad.inspect}, like gotm_rounds" do
        get path, params: bad, headers: auth_headers_for(owner)

        expect(response).to have_http_status(:unprocessable_content)
        expect(json.fetch("error")).to eq("invalid_#{bad.keys.first}")
        expect(json.fetch("message")).to start_with(bad.keys.first.to_s)
      end
    end
  end
end
