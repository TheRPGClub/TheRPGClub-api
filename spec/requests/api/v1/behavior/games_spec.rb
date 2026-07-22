# frozen_string_literal: true

require "rails_helper"

# Behavior specs for the games endpoints: list/search/filters, show, the
# admin/service-only create-from-IGDB import (bot-parity release quirks),
# update, refresh-images/releases, releases list, HLTB upsert, relations and
# the aggregate profile. All IGDB/Backblaze traffic is stubbed at the
# Igdb::Client / Gamedb::IgdbImageImporter seams — no spec makes a real HTTP call.
RSpec.describe "api/v1/games behavior", type: :request do
  describe "GET /api/v1/games" do
    it "lists matching games ordered by title with pagination meta" do
      create(:game, title: "gamesidx zz omega")
      create(:game, title: "gamesidx aa alpha")

      get "/api/v1/games", params: { q: "gamesidx" }, headers: service_headers

      expect(response).to have_http_status(:ok)
      titles = json.fetch("data").map { |g| g.fetch("title") }
      expect(titles).to eq([ "gamesidx aa alpha", "gamesidx zz omega" ])
      expect(json.fetch("meta")).to include("page" => 1, "count" => 2, "resource" => "gamedb_games")
    end

    it "serializes the documented game fields" do
      game = create(:game, description: "a fine rpg", igdb_url: "https://www.igdb.com/games/x")

      get "/api/v1/games", params: { q: game.title }, headers: service_headers

      expect(json.fetch("data").first).to include(
        "game_id" => game.game_id,
        "title" => game.title,
        "description" => "a fine rpg",
        "igdb_url" => "https://www.igdb.com/games/x",
        "cover_url" => nil,
        "gotm_won" => false,
        "nr_gotm_won" => false
      )
    end

    it "ranks an exact title match first" do
      create(:game, title: "searchrank alpha two")
      exact = create(:game, title: "searchrank alpha")

      get "/api/v1/games", params: { q: "searchrank alpha" }, headers: service_headers

      expect(json.fetch("data").first.fetch("game_id")).to eq(exact.game_id)
    end

    it "filters to GOTM winners with winner=gotm" do
      winner = create(:game, title: "winfilter won #{SecureRandom.hex(4)}")
      create(:game, title: "winfilter lost #{SecureRandom.hex(4)}")
      GotmEntry.create!(
        gamedb_game_id: winner.game_id,
        round_number: SecureRandom.random_number(1_000_000),
        month_year: "2024-03", game_index: 1
      )

      get "/api/v1/games", params: { q: "winfilter", winner: "gotm" }, headers: service_headers

      expect(json.fetch("data").map { |g| g.fetch("game_id") }).to eq([ winner.game_id ])
      expect(json.fetch("data").first).to include("gotm_won" => true)
    end

    it "filters by genre_id, matching any of several values within the dimension" do
      genre_a = create(:genre)
      genre_b = create(:genre)
      in_a = create(:game)
      in_b = create(:game)
      create(:game) # no genre
      create(:game_genre, game: in_a, genre: genre_a)
      create(:game_genre, game: in_b, genre: genre_b)

      get "/api/v1/games", params: { genre_id: [ genre_a.genre_id, genre_b.genre_id ] }, headers: service_headers

      expect(json.fetch("data").map { |g| g.fetch("game_id") }).to contain_exactly(in_a.game_id, in_b.game_id)
      expect(json.dig("meta", "count")).to eq(2)
    end

    it "paginates with page/per" do
      3.times { |i| create(:game, title: "gamespage #{i} #{SecureRandom.hex(4)}") }

      get "/api/v1/games", params: { q: "gamespage", per: 2, page: 1 }, headers: service_headers

      expect(json.fetch("data").length).to eq(2)
      expect(json.fetch("meta")).to include("per" => 2, "page" => 1, "count" => 3)
      expect(json.dig("meta", "pages")).to eq(2)
    end

    it "supports the legacy limit/offset alias" do
      3.times { |i| create(:game, title: "gamesoffset #{i} #{SecureRandom.hex(4)}") }

      get "/api/v1/games", params: { q: "gamesoffset", limit: 2, offset: 2 }, headers: service_headers

      expect(json.fetch("data").length).to eq(1)
      expect(json.fetch("meta")).to include("per" => 2, "page" => 2)
    end

    it "requires authentication" do
      get "/api/v1/games"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/games/:id" do
    it "returns the game with GOTM month info and now-playing/completion previews" do
      game = create(:game)
      GotmEntry.create!(
        gamedb_game_id: game.game_id,
        round_number: SecureRandom.random_number(1_000_000),
        month_year: "2024-03", game_index: 1
      )
      player = create(:user)
      finisher = create(:user)
      UserNowPlaying.create!(user_id: player.user_id, gamedb_game_id: game.game_id)
      UserGameCompletion.create!(user_id: finisher.user_id, gamedb_game_id: game.game_id, completion_type: "Main Story")

      get "/api/v1/games/#{game.game_id}", headers: auth_headers_for(create(:user))

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include(
        "game_id" => game.game_id,
        "title" => game.title,
        "gotm_won" => true,
        "gotm_month_year" => "2024-03",
        "nr_gotm_won" => false,
        "nr_gotm_month_year" => nil
      )
      expect(json.dig("data", "now_playing").length).to eq(1)
      expect(json.dig("data", "now_playing", 0)).to include("user_id" => player.user_id, "gamedb_game_id" => game.game_id)
      expect(json.dig("data", "completions").length).to eq(1)
      expect(json.dig("data", "completions", 0)).to include("user_id" => finisher.user_id, "completion_type" => "Main Story")
    end

    it "404s for an unknown id" do
      get "/api/v1/games/999999999", headers: service_headers

      expect(response).to have_http_status(:not_found)
      expect(json).to have_key("error")
    end

    it "requires authentication" do
      get "/api/v1/games/1"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "POST /api/v1/games (create from IGDB)" do
    let(:igdb_id) { SecureRandom.random_number(1_000_000_000) }
    let(:genre_igdb_id) { SecureRandom.random_number(1_000_000_000) }
    let(:company_igdb_id) { SecureRandom.random_number(1_000_000_000) }
    let(:collection_igdb_id) { SecureRandom.random_number(1_000_000_000) }
    let(:snes_igdb_id) { SecureRandom.random_number(1_000_000_000) }
    let(:ps_igdb_id) { SecureRandom.random_number(1_000_000_000) }
    let(:snes_ref) { { igdb_id: snes_igdb_id, name: "Spec SNES #{SecureRandom.hex(3)}" } }
    let(:ps_ref) { { igdb_id: ps_igdb_id, name: "Spec PSX #{SecureRandom.hex(3)}" } }

    let(:igdb_payload) do
      {
        igdb_id: igdb_id,
        name: "Spec Trigger #{SecureRandom.hex(4)}",
        slug: "spec-trigger-#{SecureRandom.hex(4)}",
        summary: "A time-travelling rpg.",
        url: "https://www.igdb.com/games/spec-trigger",
        total_rating: 92.5,
        first_release_date: Time.utc(1995, 3, 11),
        parent_igdb_id: nil,
        parent_game_name: nil,
        collection: { igdb_id: collection_igdb_id, name: "Spec Series #{SecureRandom.hex(3)}" },
        cover_image_id: nil,
        artworks: [],
        genres: [ { igdb_id: genre_igdb_id, name: "Spec RPG #{SecureRandom.hex(3)}" } ],
        platforms: [ snes_ref, ps_ref ],
        themes: [],
        game_modes: [],
        perspectives: [],
        engines: [],
        franchises: [],
        companies: [ { igdb_id: company_igdb_id, name: "Spec Square #{SecureRandom.hex(3)}", developer: true, publisher: true } ],
        release_dates: [
          # Japan release is the earliest on SNES but must be skipped entirely.
          { platform: snes_ref, region: 5, date: Time.utc(1995, 3, 11) },
          # NA is the earliest non-JP SNES release and should win...
          { platform: snes_ref, region: 2, date: Time.utc(1995, 8, 22) },
          # ...over the later EU release on the same platform.
          { platform: snes_ref, region: 1, date: Time.utc(1995, 12, 1) },
          # Undated rows are dropped.
          { platform: ps_ref, region: 2, date: nil },
          # A nil region falls back to Worldwide.
          { platform: ps_ref, region: nil, date: Time.utc(2001, 6, 29) }
        ]
      }
    end

    let(:igdb_client) { instance_double(Igdb::Client) }
    let(:image_importer) { instance_double(Gamedb::IgdbImageImporter, import!: []) }

    before do
      allow(Igdb::Client).to receive(:new).and_return(igdb_client)
      allow(Gamedb::IgdbImageImporter).to receive(:new).and_return(image_importer)
      allow(igdb_client).to receive(:game).with(igdb_id).and_return(igdb_payload)
    end

    it "creates the game with its taxonomy, auto-creating missing lookups" do
      expect {
        post "/api/v1/games", params: { igdb_id: igdb_id }, headers: service_headers, as: :json
      }.to change(GamedbGame, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(json.fetch("data")).to include(
        "title" => igdb_payload[:name],
        "igdb_id" => igdb_id,
        "slug" => igdb_payload[:slug],
        "description" => "A time-travelling rpg."
      )
      expect(json.fetch("images")).to eq([])

      game = GamedbGame.find_by!(igdb_id: igdb_id)
      genre = GamedbGenre.find_by!(igdb_genre_id: genre_igdb_id)
      expect(genre.name).to eq(igdb_payload[:genres].first[:name])
      expect(game.genres).to contain_exactly(genre)
      expect(game.collection.igdb_collection_id).to eq(collection_igdb_id)
      expect(game.platforms.pluck(:igdb_platform_id)).to contain_exactly(snes_igdb_id, ps_igdb_id)
      expect(game.game_companies.pluck(:role)).to contain_exactly("Developer", "Publisher")
    end

    it "synthesizes a platform_code for auto-created platforms" do
      post "/api/v1/games", params: { igdb_id: igdb_id }, headers: service_headers, as: :json

      platform = GamedbPlatform.find_by!(igdb_platform_id: snes_igdb_id)
      expected_base = snes_ref[:name].gsub(/[^A-Za-z0-9]/, "").upcase[0, 12]
      expect(platform.platform_code).to eq("#{expected_base}#{snes_igdb_id}"[0, 20])
      expect(platform.platform_name).to eq(snes_ref[:name])
    end

    it "imports one earliest non-Japanese release per platform, format null" do
      post "/api/v1/games", params: { igdb_id: igdb_id }, headers: service_headers, as: :json

      game = GamedbGame.find_by!(igdb_id: igdb_id)
      releases = game.releases.includes(:platform, :region)
      expect(releases.length).to eq(2)

      snes_release = releases.find { |r| r.platform.igdb_platform_id == snes_igdb_id }
      expect(snes_release.release_date).to eq(Time.utc(1995, 8, 22))
      expect(snes_release.region.igdb_region_id).to eq(2)
      expect(snes_release.format).to be_nil

      ps_release = releases.find { |r| r.platform.igdb_platform_id == ps_igdb_id }
      expect(ps_release.release_date).to eq(Time.utc(2001, 6, 29))
      expect(ps_release.region.region_code).to eq("WW")
    end

    it "is idempotent on igdb_id, refreshing with 200 and never duplicating" do
      post "/api/v1/games", params: { igdb_id: igdb_id }, headers: service_headers, as: :json
      expect(response).to have_http_status(:created)
      counts_before = [ GamedbGame.count, GamedbGameGenre.count, GamedbRelease.count ]

      post "/api/v1/games", params: { igdb_id: igdb_id }, headers: service_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect([ GamedbGame.count, GamedbGameGenre.count, GamedbRelease.count ]).to eq(counts_before)
    end

    it "allows an admin user" do
      post "/api/v1/games", params: { igdb_id: igdb_id }, headers: auth_headers_for(create(:user, :admin)), as: :json

      expect(response).to have_http_status(:created)
    end

    it "400s when igdb_id is missing" do
      post "/api/v1/games", params: {}, headers: service_headers, as: :json

      expect(response).to have_http_status(:bad_request)
    end

    it "400s when igdb_id is not an integer" do
      post "/api/v1/games", params: { igdb_id: "abc" }, headers: service_headers, as: :json

      expect(response).to have_http_status(:bad_request)
    end

    it "404s when the IGDB game does not exist" do
      allow(igdb_client).to receive(:game).and_return(nil)

      post "/api/v1/games", params: { igdb_id: igdb_id }, headers: service_headers, as: :json

      expect(response).to have_http_status(:not_found)
      expect(json.fetch("error")).to eq("igdb_game_not_found")
    end

    it "422s when IGDB is not configured" do
      allow(igdb_client).to receive(:game).and_raise(Igdb::Client::ConfigurationError, "IGDB_CLIENT_ID must be set")

      post "/api/v1/games", params: { igdb_id: igdb_id }, headers: service_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("error")).to eq("igdb_not_configured")
    end

    it "502s when the IGDB request fails" do
      allow(igdb_client).to receive(:game).and_raise(Igdb::Client::RequestError, "IGDB games request failed")

      post "/api/v1/games", params: { igdb_id: igdb_id }, headers: service_headers, as: :json

      expect(response).to have_http_status(:bad_gateway)
      expect(json.fetch("error")).to eq("igdb_request_failed")
    end

    it "forbids a regular user" do
      expect {
        post "/api/v1/games", params: { igdb_id: igdb_id }, headers: auth_headers_for(create(:user)), as: :json
      }.not_to change(GamedbGame, :count)

      expect(response).to have_http_status(:forbidden)
      expect(json).to eq("error" => "forbidden")
    end

    it "requires authentication" do
      post "/api/v1/games", params: { igdb_id: igdb_id }, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "PATCH /api/v1/games/:id" do
    let(:game) { create(:game, description: "old description") }

    it "updates description and featured_video_url as the service" do
      patch "/api/v1/games/#{game.game_id}",
        params: { data: { description: "new description", featured_video_url: "https://youtu.be/xyz" } },
        headers: service_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "description")).to eq("new description")
      game.reload
      expect(game.description).to eq("new description")
      expect(game.featured_video_url).to eq("https://youtu.be/xyz")
    end

    it "ignores columns outside the two writable fields" do
      original_title = game.title

      patch "/api/v1/games/#{game.game_id}",
        params: { data: { title: "Hijacked", description: "still fine" } },
        headers: service_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(game.reload.title).to eq(original_title)
      expect(game.description).to eq("still fine")
    end

    it "allows an admin user" do
      patch "/api/v1/games/#{game.game_id}",
        params: { data: { description: "admin edit" } },
        headers: auth_headers_for(create(:user, :admin)), as: :json

      expect(response).to have_http_status(:ok)
      expect(game.reload.description).to eq("admin edit")
    end

    it "forbids a regular user" do
      patch "/api/v1/games/#{game.game_id}",
        params: { data: { description: "nope" } },
        headers: auth_headers_for(create(:user)), as: :json

      expect(response).to have_http_status(:forbidden)
      expect(game.reload.description).to eq("old description")
    end

    it "404s for an unknown id" do
      patch "/api/v1/games/999999999", params: { data: { description: "x" } }, headers: service_headers, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it "400s when the data envelope is missing" do
      patch "/api/v1/games/#{game.game_id}", params: { description: "bare" }, headers: service_headers, as: :json

      expect(response).to have_http_status(:bad_request)
    end

    it "requires authentication" do
      patch "/api/v1/games/#{game.game_id}", params: { data: { description: "x" } }, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "POST /api/v1/games/:id/refresh-images" do
    it "returns the importer result" do
      game = create(:game, igdb_id: SecureRandom.random_number(1_000_000_000))
      importer = instance_double(Gamedb::IgdbImageImporter)
      allow(Gamedb::IgdbImageImporter).to receive(:new).and_return(importer)
      allow(importer).to receive(:import!).with(game.game_id.to_s).and_return(
        Gamedb::IgdbImageImporter::Result.new(
          game_id: game.game_id, igdb_id: game.igdb_id, title: game.title, igdb_title: game.title, images: []
        )
      )

      post "/api/v1/games/#{game.game_id}/refresh-images", headers: service_headers

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include(
        "game_id" => game.game_id,
        "igdb_id" => game.igdb_id,
        "title" => game.title,
        "images" => []
      )
    end

    it "422s when the game has no IGDB id" do
      game = create(:game)

      post "/api/v1/games/#{game.game_id}/refresh-images", headers: service_headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("error")).to eq("missing_igdb_id")
    end

    it "404s when the IGDB game does not exist" do
      game = create(:game, igdb_id: SecureRandom.random_number(1_000_000_000))
      importer = instance_double(Gamedb::IgdbImageImporter)
      allow(Gamedb::IgdbImageImporter).to receive(:new).and_return(importer)
      allow(importer).to receive(:import!)
        .and_raise(Gamedb::IgdbImageImporter::MissingIgdbGameError, "IGDB game #{game.igdb_id} was not found")

      post "/api/v1/games/#{game.game_id}/refresh-images", headers: service_headers

      expect(response).to have_http_status(:not_found)
      expect(json.fetch("error")).to eq("igdb_game_not_found")
    end

    it "404s for an unknown game id" do
      post "/api/v1/games/999999999/refresh-images", headers: service_headers

      expect(response).to have_http_status(:not_found)
    end

    it "forbids a regular user" do
      game = create(:game)

      post "/api/v1/games/#{game.game_id}/refresh-images", headers: auth_headers_for(create(:user))

      expect(response).to have_http_status(:forbidden)
    end

    it "requires authentication" do
      post "/api/v1/games/1/refresh-images"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "POST /api/v1/games/:id/refresh-releases" do
    let(:igdb_id) { SecureRandom.random_number(1_000_000_000) }
    let(:game) { create(:game, igdb_id: igdb_id) }
    let(:platform_ref) { { igdb_id: SecureRandom.random_number(1_000_000_000), name: "Refresh Deck #{SecureRandom.hex(3)}" } }
    let(:igdb_payload) do
      {
        igdb_id: igdb_id,
        name: game.title,
        release_dates: [
          # JP-only date is skipped; the NA one lands.
          { platform: platform_ref, region: 5, date: Time.utc(2024, 1, 1) },
          { platform: platform_ref, region: 2, date: Time.utc(2024, 6, 1) }
        ]
      }
    end
    let(:igdb_client) { instance_double(Igdb::Client) }

    before do
      allow(Igdb::Client).to receive(:new).and_return(igdb_client)
      allow(igdb_client).to receive(:game).with(igdb_id).and_return(igdb_payload)
    end

    it "replaces the game's releases and their announcements from IGDB" do
      stale_release = create(:release, game: game, release_date: Time.utc(2020, 1, 1))
      stale_announcement = create(:release_announcement, release: stale_release)

      post "/api/v1/games/#{game.game_id}/refresh-releases", headers: service_headers

      expect(response).to have_http_status(:ok)
      expect(GamedbRelease.exists?(stale_release.release_id)).to be(false)
      expect(GamedbReleaseAnnouncement.exists?(stale_announcement.release_id)).to be(false)

      releases = game.releases.reload.includes(:platform, :region)
      expect(releases.length).to eq(1)
      expect(releases.first.release_date).to eq(Time.utc(2024, 6, 1))
      expect(releases.first.platform.igdb_platform_id).to eq(platform_ref[:igdb_id])

      expect(json.fetch("data").length).to eq(1)
      expect(json.fetch("data").first).to include(
        "release_id" => releases.first.release_id,
        "platform_name" => platform_ref[:name],
        "format" => nil
      )
    end

    it "422s when the game has no IGDB id" do
      no_igdb = create(:game)

      post "/api/v1/games/#{no_igdb.game_id}/refresh-releases", headers: service_headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("error")).to eq("missing_igdb_id")
    end

    it "404s when the IGDB game does not exist" do
      allow(igdb_client).to receive(:game).and_return(nil)

      post "/api/v1/games/#{game.game_id}/refresh-releases", headers: service_headers

      expect(response).to have_http_status(:not_found)
      expect(json.fetch("error")).to eq("igdb_game_not_found")
    end

    it "404s for an unknown game id" do
      post "/api/v1/games/999999999/refresh-releases", headers: service_headers

      expect(response).to have_http_status(:not_found)
    end

    it "forbids a regular user" do
      post "/api/v1/games/#{game.game_id}/refresh-releases", headers: auth_headers_for(create(:user))

      expect(response).to have_http_status(:forbidden)
    end

    it "requires authentication" do
      post "/api/v1/games/#{game.game_id}/refresh-releases"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/games/:id/releases" do
    it "lists the game's releases date-ordered with platform/region flattened in" do
      game = create(:game)
      later = create(:release, game: game, release_date: Time.utc(2001, 6, 29))
      earlier = create(:release, game: game, release_date: Time.utc(1995, 8, 22), format: "Physical", notes: "big box")
      create(:release) # other game

      get "/api/v1/games/#{game.game_id}/releases", headers: auth_headers_for(create(:user))

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data").map { |r| r.fetch("release_id") }).to eq([ earlier.release_id, later.release_id ])
      expect(json.fetch("data").first).to include(
        "game_id" => game.game_id,
        "platform_id" => earlier.platform_id,
        "region_id" => earlier.region_id,
        "format" => "Physical",
        "notes" => "big box",
        "platform_code" => earlier.platform.platform_code,
        "platform_name" => earlier.platform.platform_name,
        "region_code" => earlier.region.region_code,
        "region_name" => earlier.region.region_name
      )
    end

    it "404s for an unknown game" do
      get "/api/v1/games/999999999/releases", headers: service_headers

      expect(response).to have_http_status(:not_found)
    end

    it "requires authentication" do
      get "/api/v1/games/1/releases"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "POST /api/v1/games/:id/hltb" do
    let(:game) { create(:game) }
    let(:payload) do
      {
        data: {
          name: "Spec Trigger", url: "https://howlongtobeat.com/game/123",
          image_url: "https://howlongtobeat.com/games/123.jpg",
          main: "23 Hours", main_sides: "30 Hours", completionist: "40 Hours",
          source_query: "spec trigger"
        }
      }
    end

    it "creates the HLTB cache row, mapping the logical names to hltb_ columns" do
      expect {
        post "/api/v1/games/#{game.game_id}/hltb", params: payload, headers: service_headers, as: :json
      }.to change(RpgClubHltbCache, :count).by(1)

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include(
        "name" => "Spec Trigger",
        "url" => "https://howlongtobeat.com/game/123",
        "image_url" => "https://howlongtobeat.com/games/123.jpg",
        "main" => "23 Hours",
        "main_sides" => "30 Hours",
        "completionist" => "40 Hours",
        "source_query" => "spec trigger"
      )

      cache = RpgClubHltbCache.find_by!(gamedb_game_id: game.game_id)
      expect(cache.hltb_name).to eq("Spec Trigger")
      expect(cache.hltb_url).to eq("https://howlongtobeat.com/game/123")
      expect(cache.main).to eq("23 Hours")
    end

    it "upserts on gamedb_game_id instead of inserting a second row" do
      post "/api/v1/games/#{game.game_id}/hltb", params: payload, headers: service_headers, as: :json

      expect {
        post "/api/v1/games/#{game.game_id}/hltb",
          params: { data: { main: "25 Hours" } }, headers: auth_headers_for(create(:user, :admin)), as: :json
      }.not_to change(RpgClubHltbCache, :count)

      expect(response).to have_http_status(:ok)
      expect(RpgClubHltbCache.find_by!(gamedb_game_id: game.game_id).main).to eq("25 Hours")
    end

    it "forbids a regular user" do
      expect {
        post "/api/v1/games/#{game.game_id}/hltb", params: payload, headers: auth_headers_for(create(:user)), as: :json
      }.not_to change(RpgClubHltbCache, :count)

      expect(response).to have_http_status(:forbidden)
    end

    it "404s for an unknown game" do
      post "/api/v1/games/999999999/hltb", params: payload, headers: service_headers, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it "400s when the data envelope is missing" do
      post "/api/v1/games/#{game.game_id}/hltb", params: { name: "bare" }, headers: service_headers, as: :json

      expect(response).to have_http_status(:bad_request)
    end

    it "requires authentication" do
      post "/api/v1/games/#{game.game_id}/hltb", params: payload, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/games/:id/relations" do
    it "returns the taxonomy slices for the game" do
      game = create(:game)
      genre = create(:genre)
      platform = create(:platform)
      create(:game_genre, game: game, genre: genre)
      create(:game_platform, game: game, platform: platform)
      release = create(:release, game: game, platform: platform, release_date: Time.utc(2020, 3, 3))
      alternate = create(:game)
      low, high = [ game.game_id, alternate.game_id ].minmax
      GamedbGameAlternate.create!(game_id: low, alt_game_id: high)

      get "/api/v1/games/#{game.game_id}/relations", headers: auth_headers_for(create(:user))

      expect(response).to have_http_status(:ok)
      data = json.fetch("data")
      expect(data.fetch("genres")).to contain_exactly(hash_including("genre_id" => genre.genre_id, "name" => genre.name))
      expect(data.fetch("platforms")).to contain_exactly(
        hash_including("platform_id" => platform.platform_id, "platform_name" => platform.platform_name)
      )
      expect(data.fetch("releases")).to contain_exactly(hash_including("release_id" => release.release_id))
      expect(data.fetch("alternates")).to contain_exactly(hash_including("game_id" => alternate.game_id))
      expect(data.fetch("collection")).to be_nil
      expect(data.fetch("franchises")).to eq([])
      expect(data.fetch("companies")).to eq([])
    end

    it "404s for an unknown game" do
      get "/api/v1/games/999999999/relations", headers: service_headers

      expect(response).to have_http_status(:not_found)
    end

    it "requires authentication" do
      get "/api/v1/games/1/relations"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/games/:id/profile" do
    it "returns the aggregate payload in one request" do
      game = create(:game)
      GotmEntry.create!(
        gamedb_game_id: game.game_id,
        round_number: SecureRandom.random_number(1_000_000),
        month_year: "2023-11", game_index: 1
      )
      image = create(:game_image, :primary, game: game)
      RpgClubHltbCache.create!(gamedb_game_id: game.game_id, hltb_name: "Spec HLTB", main: "12 Hours")
      player = create(:user)
      UserNowPlaying.create!(user_id: player.user_id, gamedb_game_id: game.game_id)

      get "/api/v1/games/#{game.game_id}/profile", headers: auth_headers_for(create(:user))

      expect(response).to have_http_status(:ok)
      data = json.fetch("data")
      expect(data.keys).to contain_exactly(
        "game", "relations", "now_playing", "completions", "threads",
        "primary_image", "associations", "collection_owners", "hltb"
      )
      expect(data.fetch("game")).to include(
        "game_id" => game.game_id,
        "gotm_won" => true,
        "gotm_month_year" => "2023-11"
      )
      expect(data.fetch("now_playing").length).to eq(1)
      expect(data.fetch("completions")).to eq([])
      expect(data.fetch("threads")).to eq([])
      expect(data.fetch("primary_image")).to eq("url" => image.url)
      expect(data.dig("associations", "gotm_wins").length).to eq(1)
      expect(data.dig("associations", "nr_gotm_wins")).to eq([])
      expect(data.fetch("collection_owners")).to eq([])
      expect(data.fetch("hltb")).to include("name" => "Spec HLTB", "main" => "12 Hours")
    end

    it "404s for an unknown game" do
      get "/api/v1/games/999999999/profile", headers: service_headers

      expect(response).to have_http_status(:not_found)
    end

    it "requires authentication" do
      get "/api/v1/games/1/profile"

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
