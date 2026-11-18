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

    it "ignores a leading or trailing article when matching and ranking" do
      create(:game, title: "articlerank last of us part ii")
      exact = create(:game, title: "The articlerank Last of Us")

      [ "The articlerank Last of Us", "articlerank last of us", "articlerank Last of Us, The" ].each do |q|
        get "/api/v1/games", params: { q: q }, headers: service_headers

        expect(json.fetch("data").first.fetch("game_id")).to eq(exact.game_id)
      end
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

    describe "sort" do
      def ids
        json.fetch("data").map { |g| g.fetch("game_id") }
      end

      let!(:oldest) { create(:game, title: "sort a oldest", created_at: 3.days.ago) }
      let!(:newest_b) { create(:game, title: "sort c newest", created_at: 1.day.ago) }
      let!(:newest_a) { create(:game, title: "sort b newest", created_at: newest_b.created_at) }
      let!(:middle) { create(:game, title: "sort d middle", created_at: 2.days.ago) }

      it "defaults to title order" do
        get "/api/v1/games", headers: service_headers

        expect(ids).to eq([ oldest, newest_a, newest_b, middle ].map(&:game_id))
      end

      it "orders newest-added first with sort=newest, title breaking ties" do
        get "/api/v1/games", params: { sort: "newest" }, headers: service_headers

        expect(response).to have_http_status(:ok)
        expect(ids).to eq([ newest_a, newest_b, middle, oldest ].map(&:game_id))
      end

      it "pages and filters the newest order" do
        create(:gotm_entry, game: middle)
        create(:gotm_entry, game: oldest)

        get "/api/v1/games", params: { sort: "newest", per: 1, page: 2 }, headers: service_headers
        expect(ids).to eq([ newest_b.game_id ])
        expect(json.fetch("meta")).to include("count" => 4, "page" => 2)

        get "/api/v1/games", params: { sort: "newest", winner: "gotm" }, headers: service_headers
        expect(ids).to eq([ middle, oldest ].map(&:game_id))
      end

      it "ignores sort when q is present, keeping relevance order" do
        get "/api/v1/games", params: { sort: "newest", q: "sort d middle" }, headers: service_headers

        expect(ids.first).to eq(middle.game_id)

        get "/api/v1/games", params: { sort: "newest", q: "sort" }, headers: service_headers
        expect(ids).to eq([ oldest, newest_a, newest_b, middle ].map(&:game_id))
      end

      it "rejects an unknown sort with 422" do
        get "/api/v1/games", params: { sort: "rating" }, headers: service_headers

        expect(response).to have_http_status(:unprocessable_content)
        expect(json).to include("error" => "invalid_sort")
        expect(json.fetch("message")).to include("title", "newest")
      end
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
          # A Japan-first game: Japan is the earliest SNES release and is kept...
          { platform: snes_ref, region: 5, date: Date.new(1995, 3, 11), date_precision: "day" },
          # ...beside each other region's earliest SNES release...
          { platform: snes_ref, region: 2, date: Date.new(1995, 8, 22), date_precision: "day" },
          { platform: snes_ref, region: 1, date: Date.new(1995, 12, 1), date_precision: "day" },
          # ...while a later date in the same region loses.
          { platform: snes_ref, region: 2, date: Date.new(1996, 2, 1), date_precision: "day" },
          # A TBA row is kept as a TBA Release when its platform and region has nothing else.
          { platform: ps_ref, region: 2, date: nil, date_precision: "tba" },
          # A nil region falls back to Worldwide.
          { platform: ps_ref, region: nil, date: Date.new(2001, 6, 29), date_precision: "day" }
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

    it "imports the earliest IGDB Release per platform per region, Japan included, format null" do
      post "/api/v1/games", params: { igdb_id: igdb_id }, headers: service_headers, as: :json

      game = GamedbGame.find_by!(igdb_id: igdb_id)
      releases = game.releases.includes(:platform, :region)
      expect(releases.length).to eq(5)
      expect(releases.map(&:source)).to all(eq("igdb"))
      expect(releases.map(&:format)).to all(be_nil)

      snes_releases = releases.select { |r| r.platform.igdb_platform_id == snes_igdb_id }
      expect(snes_releases.to_h { |r| [ r.region.igdb_region_id, r.release_date ] }).to eq(
        5 => Date.new(1995, 3, 11),
        2 => Date.new(1995, 8, 22),
        1 => Date.new(1995, 12, 1)
      )

      ps_releases = releases.select { |r| r.platform.igdb_platform_id == ps_igdb_id }
      expect(ps_releases.to_h { |r| [ r.region.region_code, [ r.release_date, r.date_precision ] ] }).to eq(
        "WW" => [ Date.new(2001, 6, 29), "day" ],
        "NA" => [ nil, "tba" ]
      )
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

    it "allows a Members role holder" do
      post "/api/v1/games", params: { igdb_id: igdb_id }, headers: auth_headers_for(create(:user, role_member: true)), as: :json

      expect(response).to have_http_status(:created)
      expect(json.fetch("data")).to include("igdb_id" => igdb_id, "title" => igdb_payload[:name])
    end

    it "returns the existing game to a member without re-importing it" do
      existing = create(:game, igdb_id: igdb_id, title: "Already Here #{SecureRandom.hex(3)}")

      expect {
        post "/api/v1/games", params: { igdb_id: igdb_id }, headers: auth_headers_for(create(:user, role_member: true)), as: :json
      }.not_to change(GamedbGame, :count)

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("game_id" => existing.game_id, "title" => existing.title)
      expect(json.fetch("images")).to eq([])
      expect(igdb_client).not_to have_received(:game)
      expect(image_importer).not_to have_received(:import!)
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

    it "allows a signed-in user without the Members role, as anyone who can donate a key" do
      expect {
        post "/api/v1/games", params: { igdb_id: igdb_id }, headers: auth_headers_for(create(:user)), as: :json
      }.to change(GamedbGame, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(json.fetch("data")).to include("igdb_id" => igdb_id, "title" => igdb_payload[:name])
    end

    it "returns the existing game to a user without roles without re-importing it" do
      existing = create(:game, igdb_id: igdb_id, title: "Already Here #{SecureRandom.hex(3)}")

      expect {
        post "/api/v1/games", params: { igdb_id: igdb_id }, headers: auth_headers_for(create(:user)), as: :json
      }.not_to change(GamedbGame, :count)

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("game_id" => existing.game_id)
      expect(json.fetch("images")).to eq([])
      expect(igdb_client).not_to have_received(:game)
      expect(image_importer).not_to have_received(:import!)
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
          # The earliest NA date lands; the later one loses.
          { platform: platform_ref, region: 2, date: Date.new(2024, 9, 1), date_precision: "day" },
          { platform: platform_ref, region: 2, date: Date.new(2024, 6, 1), date_precision: "day" }
        ]
      }
    end
    let(:igdb_client) { instance_double(Igdb::Client) }

    before do
      allow(Igdb::Client).to receive(:new).and_return(igdb_client)
      allow(igdb_client).to receive(:game).with(igdb_id).and_return(igdb_payload)
    end

    def announcement_ids_for(game)
      get "/api/v1/games/#{game.game_id}/release_announcements", headers: service_headers
      json.fetch("data").map { |announcement| announcement.fetch("release_id") }
    end

    def refresh!
      post "/api/v1/games/#{game.game_id}/refresh-releases", headers: service_headers
      expect(response).to have_http_status(:ok)
    end

    def igdb_reports(*dates)
      allow(igdb_client).to receive(:game).with(igdb_id).and_return(
        igdb_id: igdb_id, name: game.title,
        release_dates: dates.map { |date| { platform: platform_ref, region: 2, date: date.to_date, date_precision: "day" } }
      )
    end

    def releases_of(game)
      get "/api/v1/games/#{game.game_id}/releases", headers: service_headers
      json.fetch("data")
    end

    def announcements_of(game)
      get "/api/v1/games/#{game.game_id}/release_announcements", headers: service_headers
      json.fetch("data")
    end

    def due_feed
      get "/api/v1/release_announcements/due", headers: service_headers
      json.fetch("data")
    end

    def sync_announcements!
      patch "/api/v1/games/#{game.game_id}/release_announcements", headers: service_headers
      expect(response).to have_http_status(:ok)
    end

    it "keeps an unmatched Manual Release and adds the IGDB Release beside it" do
      manual = create(:release, game: game, release_date: Time.utc(2020, 1, 1), notes: "hand entered")
      announcement = create(:release_announcement, release: manual)

      post "/api/v1/games/#{game.game_id}/refresh-releases", headers: service_headers

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to contain_exactly(
        hash_including("release_id" => manual.release_id, "source" => "manual", "notes" => "hand entered",
          "release_date" => "2020-01-01"),
        hash_including("platform_name" => platform_ref[:name], "source" => "igdb", "format" => nil,
          "release_date" => "2024-06-01")
      )
      igdb_release_id = json.fetch("data").find { |release| release["source"] == "igdb" }.fetch("release_id")
      expect(announcement_ids_for(game)).to contain_exactly(announcement.release_id, igdb_release_id)
    end

    it "reports how many releases the refresh added" do
      post "/api/v1/games/#{game.game_id}/refresh-releases", headers: service_headers

      expect(response).to have_http_status(:ok)
      expect(json.fetch("meta")).to eq("added" => 1, "total" => 1)
    end

    it "reports no additions when IGDB has nothing new" do
      post "/api/v1/games/#{game.game_id}/refresh-releases", headers: service_headers
      post "/api/v1/games/#{game.game_id}/refresh-releases", headers: service_headers

      expect(json.fetch("meta")).to eq("added" => 0, "total" => 1)
    end

    describe "in-place refresh (ADR 0009)" do
      let(:in_window_date) { 5.days.from_now.utc.beginning_of_day }
      let(:igdb_platform) { GamedbPlatform.create!(igdb_platform_id: platform_ref[:igdb_id], platform_name: platform_ref[:name], platform_code: "RD#{SecureRandom.hex(4)}") }
      let(:north_america) do
        GamedbRegion.create_with(region_code: "NA", region_name: "North America").find_or_create_by!(igdb_region_id: 2)
      end

      it "updates the same IGDB Release when IGDB moves its date" do
        igdb_reports(Time.utc(2030, 3, 1))
        refresh!
        release_id = releases_of(game).sole.fetch("release_id")

        igdb_reports(Time.utc(2030, 4, 15))
        refresh!

        expect(releases_of(game)).to contain_exactly(
          hash_including("release_id" => release_id, "source" => "igdb", "release_date" => "2030-04-15")
        )
      end

      it "adopts the oldest matching Manual Release instead of duplicating it" do
        oldest = create(:release, game: game, platform: igdb_platform, region: north_america,
          release_date: Time.utc(2029, 1, 1), notes: "staff entry")
        newer = create(:release, game: game, platform: igdb_platform, region: north_america,
          release_date: Time.utc(2029, 2, 2))
        igdb_reports(Time.utc(2030, 3, 1))

        refresh!

        expect(releases_of(game)).to contain_exactly(
          hash_including("release_id" => oldest.release_id, "source" => "igdb", "notes" => "staff entry",
            "release_date" => "2030-03-01"),
          hash_including("release_id" => newer.release_id, "source" => "manual",
            "release_date" => "2029-02-02")
        )
      end

      it "removes an IGDB Release that IGDB stops reporting, with its unsent announcement" do
        igdb_reports(Time.utc(2030, 3, 1))
        refresh!
        sync_announcements!
        expect(announcements_of(game).length).to eq(1)

        igdb_reports
        refresh!

        expect(releases_of(game)).to eq([])
        expect(announcements_of(game)).to eq([])
      end

      it "moves an unsent announcement with its Release's new date" do
        igdb_reports(Time.utc(2030, 3, 1))
        refresh!
        sync_announcements!

        igdb_reports(Time.utc(2030, 4, 15))
        refresh!

        expect(announcements_of(game)).to contain_exactly(
          hash_including("announce_at" => "2030-04-08T00:00:00.000Z", "sent_at" => nil, "skipped_at" => nil)
        )
      end

      it "never resets a sent announcement when the date moves" do
        igdb_reports(Time.utc(2030, 3, 1))
        refresh!
        sync_announcements!
        release_id = releases_of(game).sole.fetch("release_id")
        patch "/api/v1/release_announcements/#{release_id}",
          params: { data: { sent_at: "2030-02-22T12:00:00Z" } }, headers: service_headers, as: :json

        igdb_reports(Time.utc(2030, 4, 15))
        refresh!
        sync_announcements!

        expect(announcements_of(game)).to contain_exactly(
          hash_including("release_id" => release_id, "announce_at" => "2030-02-22T00:00:00.000Z",
            "sent_at" => "2030-02-22T12:00:00.000Z")
        )
      end

      it "does not offer an announcement again after a refresh inside its 7-day window" do
        igdb_reports(in_window_date)
        refresh!
        sync_announcements!
        offered = due_feed.sole
        patch "/api/v1/release_announcements/#{offered.fetch("release_id")}",
          params: { data: { sent_at: Time.current.iso8601 } }, headers: service_headers, as: :json

        refresh!
        sync_announcements!

        expect(due_feed).to eq([])
      end
    end

    describe "Releases per platform per region, Japan included (api#391)" do
      let(:japan) { 5 }
      let(:north_america) { 2 }
      let(:europe) { 1 }
      let(:in_window_date) { 5.days.from_now.utc.beginning_of_day }

      # Each pair is [IGDB region, date], all on the one platform.
      def igdb_reports_regions(*pairs)
        allow(igdb_client).to receive(:game).with(igdb_id).and_return(
          igdb_id: igdb_id, name: game.title,
          release_dates: pairs.map do |region, date|
            { platform: platform_ref, region: region, date: date.to_date, date_precision: "day" }
          end
        )
      end

      def release_id_in(region_code)
        releases_of(game).find { |release| release.fetch("region_code") == region_code }.fetch("release_id")
      end

      def send_announcement!(release_id)
        patch "/api/v1/release_announcements/#{release_id}",
          params: { data: { sent_at: Time.current.iso8601 } }, headers: service_headers, as: :json
        expect(response).to have_http_status(:ok)
      end

      it "keeps one IGDB Release per region for NA, EU and JP dates on one platform" do
        igdb_reports_regions(
          [ north_america, Time.utc(2030, 6, 1) ],
          [ europe, Time.utc(2030, 6, 5) ],
          [ japan, Time.utc(2030, 5, 1) ],
          [ north_america, Time.utc(2030, 7, 1) ]
        )

        refresh!

        expect(releases_of(game)).to contain_exactly(
          hash_including("region_code" => "NA", "source" => "igdb", "release_date" => "2030-06-01"),
          hash_including("region_code" => "EU", "source" => "igdb", "release_date" => "2030-06-05"),
          hash_including("region_code" => "JP", "source" => "igdb", "release_date" => "2030-05-01")
        )
      end

      it "keeps both the Japanese and the western Releases of a Japan-first game across refreshes" do
        igdb_reports_regions([ japan, Time.utc(2030, 3, 1) ], [ north_america, Time.utc(2030, 9, 1) ])
        refresh!
        before = releases_of(game).map { |release| release.fetch("release_id") }

        refresh!

        expect(releases_of(game)).to contain_exactly(
          hash_including("region_code" => "JP", "release_date" => "2030-03-01"),
          hash_including("region_code" => "NA", "release_date" => "2030-09-01")
        )
        expect(releases_of(game).map { |release| release.fetch("release_id") }).to match_array(before)
      end

      it "offers the earliest Release outside Japan in the due feed for a game that has both" do
        igdb_reports_regions(
          [ japan, in_window_date - 1.day ],
          [ north_america, in_window_date ],
          [ europe, in_window_date + 1.day ]
        )
        refresh!
        sync_announcements!

        expect(due_feed.map { |row| row.fetch("release_id") }).to eq([ release_id_in("NA") ])
      end

      it "offers the earliest Japanese Release in the due feed for a Japan-only game" do
        igdb_reports_regions([ japan, in_window_date ])
        refresh!
        sync_announcements!

        expect(due_feed.map { |row| row.fetch("release_id") }).to eq([ release_id_in("JP") ])
      end

      it "offers one announcement for same-day Releases in several regions" do
        igdb_reports_regions(
          [ japan, in_window_date ],
          [ north_america, in_window_date ],
          [ europe, in_window_date ]
        )
        refresh!
        sync_announcements!

        offered = due_feed.map { |row| row.fetch("release_id") }
        expect(offered.length).to eq(1)
        expect(offered).not_to include(release_id_in("JP"))
      end

      it "does not announce a game again when its announced Release moves later" do
        igdb_reports_regions([ north_america, in_window_date ], [ europe, in_window_date ])
        refresh!
        sync_announcements!
        send_announcement!(due_feed.sole.fetch("release_id"))

        igdb_reports_regions([ north_america, in_window_date + 1.day ], [ europe, in_window_date ])
        refresh!
        sync_announcements!

        expect(due_feed).to eq([])
      end

      it "does not announce a game again when IGDB drops its announced Release" do
        igdb_reports_regions([ north_america, in_window_date ], [ europe, in_window_date + 1.day ])
        refresh!
        sync_announcements!
        send_announcement!(release_id_in("NA"))
        expect(due_feed).to eq([])

        igdb_reports_regions([ europe, in_window_date + 1.day ])
        refresh!
        sync_announcements!

        expect(releases_of(game)).to contain_exactly(hash_including("region_code" => "EU"))
        expect(due_feed).to eq([])
      end

      it "does not announce a Japan-only game again when a western Release appears" do
        igdb_reports_regions([ japan, in_window_date ])
        refresh!
        sync_announcements!
        send_announcement!(release_id_in("JP"))

        igdb_reports_regions([ japan, in_window_date ], [ north_america, in_window_date + 1.day ])
        refresh!
        sync_announcements!

        expect(due_feed).to eq([])
      end
    end

    describe "Date Precision and TBA Releases (api#392)" do
      let(:in_window_date) { 5.days.from_now.utc.to_date }

      # Each row is [IGDB region, date, Date Precision] as the IGDB client maps it.
      def igdb_reports_precisions(*rows)
        allow(igdb_client).to receive(:game).with(igdb_id).and_return(
          igdb_id: igdb_id, name: game.title,
          release_dates: rows.map do |region, date, precision|
            { platform: platform_ref, region: region, date: date, date_precision: precision }
          end
        )
      end

      it "refreshes a game IGDB lists for Q3 2027 into a `quarter` Release dated 2027-07-01" do
        igdb_reports_precisions([ 2, Date.new(2027, 7, 1), "quarter" ])

        refresh!

        expect(releases_of(game)).to contain_exactly(
          hash_including("release_date" => "2027-07-01", "date_precision" => "quarter", "source" => "igdb")
        )
      end

      it "refreshes a month-only date into a `month` Release and a year-only date into a `year` Release" do
        igdb_reports_precisions([ 2, Date.new(2027, 3, 1), "month" ], [ 1, Date.new(2028, 1, 1), "year" ])

        refresh!

        expect(releases_of(game)).to contain_exactly(
          hash_including("region_code" => "NA", "release_date" => "2027-03-01", "date_precision" => "month"),
          hash_including("region_code" => "EU", "release_date" => "2028-01-01", "date_precision" => "year")
        )
      end

      it "refreshes a game IGDB lists only as TBA into one `tba` Release with no date" do
        igdb_reports_precisions([ 2, nil, "tba" ], [ 2, nil, "tba" ])

        refresh!

        expect(releases_of(game)).to contain_exactly(
          hash_including("release_date" => nil, "date_precision" => "tba", "source" => "igdb")
        )
      end

      it "prefers an earlier exact or vague date over TBA for the same platform and region" do
        igdb_reports_precisions(
          [ 2, nil, "tba" ], [ 2, Date.new(2027, 10, 1), "quarter" ],
          [ 1, Date.new(2027, 5, 9), "day" ], [ 1, nil, "tba" ]
        )

        refresh!

        expect(releases_of(game)).to contain_exactly(
          hash_including("region_code" => "NA", "release_date" => "2027-10-01", "date_precision" => "quarter"),
          hash_including("region_code" => "EU", "release_date" => "2027-05-09", "date_precision" => "day")
        )
      end

      it "prefers a more precise date that falls inside a vague date's period for the same platform and region" do
        igdb_reports_precisions(
          [ 2, Date.new(2027, 7, 1), "quarter" ], [ 2, Date.new(2027, 8, 14), "day" ],
          [ 1, Date.new(2027, 1, 1), "year" ], [ 1, Date.new(2027, 5, 1), "month" ],
          [ 3, Date.new(2027, 4, 1), "quarter" ], [ 3, Date.new(2027, 8, 14), "day" ]
        )

        refresh!

        expect(releases_of(game)).to contain_exactly(
          hash_including("region_code" => "NA", "release_date" => "2027-08-14", "date_precision" => "day"),
          hash_including("region_code" => "EU", "release_date" => "2027-05-01", "date_precision" => "month"),
          hash_including("region_code" => "AUS", "release_date" => "2027-04-01", "date_precision" => "quarter")
        )
      end

      it "sharpens a vague Release into an exact day in place" do
        igdb_reports_precisions([ 2, Date.new(2027, 7, 1), "quarter" ])
        refresh!
        release_id = releases_of(game).sole.fetch("release_id")

        igdb_reports_precisions([ 2, Date.new(2027, 8, 14), "day" ])
        refresh!

        expect(releases_of(game)).to contain_exactly(
          hash_including("release_id" => release_id, "release_date" => "2027-08-14", "date_precision" => "day")
        )
      end

      it "includes the Date Precision in the relations payload" do
        igdb_reports_precisions([ 2, Date.new(2027, 3, 1), "month" ])
        refresh!

        get "/api/v1/games/#{game.game_id}/relations", headers: service_headers

        expect(json.dig("data", "releases")).to contain_exactly(
          hash_including("release_date" => "2027-03-01", "date_precision" => "month")
        )
      end

      it "schedules announcements only for `day` Releases" do
        igdb_reports_precisions(
          [ 2, Date.new(2030, 3, 1), "month" ], [ 1, Date.new(2030, 7, 1), "quarter" ],
          [ 3, Date.new(2030, 1, 1), "year" ], [ 4, nil, "tba" ], [ 8, Date.new(2030, 9, 9), "day" ]
        )
        refresh!

        sync_announcements!

        ww_release = releases_of(game).find { |release| release.fetch("date_precision") == "day" }
        expect(announcements_of(game).map { |row| row.fetch("release_id") }).to eq([ ww_release.fetch("release_id") ])
      end

      it "never offers a vague Release in the due feed, even when it is the earliest" do
        igdb_reports_precisions([ 2, in_window_date.beginning_of_month, "month" ], [ 1, in_window_date, "day" ])
        refresh!
        sync_announcements!

        expect(due_feed).to contain_exactly(hash_including("release_date" => in_window_date.iso8601))
      end

      it "makes the earliest `day` Release canonical when an earlier Release is vague" do
        igdb_reports_precisions([ 2, Date.new(2030, 3, 1), "month" ], [ 1, Date.new(2030, 3, 20), "day" ])
        refresh!

        sync_announcements!

        expect(announcements_of(game)).to contain_exactly(hash_including("skipped_at" => nil, "skip_reason" => nil))
      end

      it "drops the unsent announcement of a `day` Release that turns vague" do
        igdb_reports_precisions([ 2, in_window_date, "day" ])
        refresh!
        sync_announcements!
        expect(due_feed.length).to eq(1)

        igdb_reports_precisions([ 2, in_window_date.beginning_of_month, "month" ])
        refresh!
        sync_announcements!

        expect(announcements_of(game)).to eq([])
        expect(due_feed).to eq([])
      end

      it "drops the unsent announcement of a `day` Release that turns TBA" do
        igdb_reports_precisions([ 2, Date.new(2030, 3, 1), "day" ])
        refresh!
        sync_announcements!

        igdb_reports_precisions([ 2, nil, "tba" ])
        refresh!

        expect(releases_of(game)).to contain_exactly(hash_including("date_precision" => "tba"))
        expect(announcements_of(game)).to eq([])
      end
    end

    describe "the announcement schedule after a refresh, without the bot's PATCH" do
      let(:in_window_date) { 5.days.from_now.utc.to_date }

      # Each row is [IGDB region, date, Date Precision], all on the one platform.
      def igdb_reports_rows(*rows)
        allow(igdb_client).to receive(:game).with(igdb_id).and_return(
          igdb_id: igdb_id, name: game.title,
          release_dates: rows.map do |region, date, precision|
            { platform: platform_ref, region: region, date: date, date_precision: precision || "day" }
          end
        )
      end

      def release_id_in(region_code)
        releases_of(game).find { |release| release.fetch("region_code") == region_code }.fetch("release_id")
      end

      it "schedules the announcement of a new `day` Release" do
        igdb_reports_rows([ 2, in_window_date ])

        refresh!

        expect(due_feed.map { |row| row.fetch("release_id") }).to eq([ release_id_in("NA") ])
      end

      it "schedules a TBA Release's announcement once it becomes an exact day" do
        igdb_reports_rows([ 2, nil, "tba" ])
        refresh!
        expect(announcements_of(game)).to eq([])

        igdb_reports_rows([ 2, in_window_date ])
        refresh!

        expect(announcements_of(game)).to contain_exactly(
          hash_including("announce_at" => (in_window_date - 7).iso8601 + "T00:00:00.000Z", "skipped_at" => nil)
        )
        expect(due_feed.length).to eq(1)
      end

      it "skips the Releases that are not canonical" do
        igdb_reports_rows([ 2, in_window_date ], [ 1, in_window_date + 1 ], [ 3, in_window_date ])

        refresh!

        expect(announcements_of(game).to_h { |row| [ row.fetch("release_id"), row.fetch("skip_reason") ] }).to eq(
          release_id_in("NA") => nil,
          release_id_in("EU") => "port-only-release",
          release_id_in("AUS") => "same-day-platform-duplicate"
        )
      end

      it "moves the canonical announcement when IGDB moves the canonical Release later" do
        igdb_reports_rows([ 2, in_window_date ], [ 1, in_window_date + 1 ])
        refresh!

        igdb_reports_rows([ 2, in_window_date + 2 ], [ 1, in_window_date + 1 ])
        refresh!

        expect(announcements_of(game).to_h { |row| [ row.fetch("release_id"), row.fetch("skip_reason") ] }).to eq(
          release_id_in("NA") => "port-only-release",
          release_id_in("EU") => nil
        )
        expect(due_feed.map { |row| row.fetch("release_id") }).to eq([ release_id_in("EU") ])
      end

      it "reschedules a skipped Release that moved before it becomes canonical, so it is not announced early" do
        igdb_reports_rows([ 2, in_window_date ], [ 1, in_window_date + 1 ])
        refresh!

        igdb_reports_rows([ 2, in_window_date + 120 ], [ 1, in_window_date + 60 ])
        refresh!

        expect(announcements_of(game).find { |row| row.fetch("release_id") == release_id_in("EU") }).to include(
          "announce_at" => "#{(in_window_date + 53).iso8601}T00:00:00.000Z", "skipped_at" => nil
        )
        expect(due_feed).to eq([])
      end
    end

    it "allows a Members role holder" do
      post "/api/v1/games/#{game.game_id}/refresh-releases", headers: auth_headers_for(create(:user, role_member: true))

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data").length).to eq(1)
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

    it "forbids a user without the Members role" do
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
        "region_name" => earlier.region.region_name,
        "source" => "manual",
        "release_date" => "1995-08-22",
        "date_precision" => "day"
      )
    end

    it "orders the releases as the Release Calendar places them" do
      game = create(:game)
      platform = create(:platform, platform_name: "Only Platform")
      at = ->(date, precision) { create(:release, game: game, platform: platform, release_date: date, date_precision: precision) }
      tba = at.call(nil, "tba")
      year = at.call(Date.new(2027, 1, 1), "year")
      quarter = at.call(Date.new(2027, 7, 1), "quarter")
      day = at.call(Date.new(2027, 8, 14), "day")
      month = at.call(Date.new(2027, 8, 1), "month")
      late_day = at.call(Date.new(2027, 9, 30), "day")

      get "/api/v1/games/#{game.game_id}/releases", headers: auth_headers_for(create(:user))

      expect(json.fetch("data").map { |r| r.fetch("release_id") })
        .to eq([ month, day, late_day, quarter, year, tba ].map(&:release_id))
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

    it "lets a Members role holder save times" do
      member = auth_headers_for(create(:user, role_member: true))

      expect {
        post "/api/v1/games/#{game.game_id}/hltb", params: payload, headers: member, as: :json
      }.to change(RpgClubHltbCache, :count).by(1)

      expect(response).to have_http_status(:ok)
    end

    it "lets a Moderator save times" do
      post "/api/v1/games/#{game.game_id}/hltb", params: payload,
        headers: auth_headers_for(create(:user, role_moderator: true)), as: :json

      expect(response).to have_http_status(:ok)
    end

    it "forbids a signed-in user without the Members role" do
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
      expect(data.fetch("releases")).to contain_exactly(hash_including("release_id" => release.release_id, "source" => "manual"))
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
