# frozen_string_literal: true

require "rails_helper"

# Franchise editing (spec api#442, ticket api#443). Regulars and above link
# and unlink games, mark Mainline and create Franchises; those edits survive
# IGDB re-imports. Members read a Franchise's page: its games grouped as
# Mainline, Other and Add-ons, each Add-on under its parent game.
RSpec.describe "Franchise editing", type: :request do
  let(:member) { create(:user, role_member: true) }
  let(:regular) { create(:user, role_member: true, role_regular: true) }
  let(:franchise) { create(:franchise, name: "Final Fantasy") }

  def link(game, as:, mainline: nil, into: franchise)
    data = mainline.nil? ? {} : { mainline: mainline }
    put "/api/v1/franchises/#{into.franchise_id}/games/#{game.game_id}", params: { data: data },
      headers: auth_headers_for(as), as: :json
  end

  def unlink(game, as:, from: franchise)
    delete "/api/v1/franchises/#{from.franchise_id}/games/#{game.game_id}", headers: auth_headers_for(as)
  end

  def franchise_page(as: member, of: franchise)
    get "/api/v1/franchises/#{of.franchise_id}", headers: auth_headers_for(as)
    expect(response).to have_http_status(:ok)
    json.fetch("data")
  end

  def titles(group) = group.map { |entry| entry.fetch("title") }

  describe "linking a game" do
    it "lets a Regular add a game to a Franchise by hand" do
      game = create(:game, title: "Final Fantasy Tactics")

      link(game, as: regular)

      expect(response).to have_http_status(:ok)
      expect(titles(franchise_page.dig("games", "other"))).to eq([ "Final Fantasy Tactics" ])
    end

    it "answers with the link, made by hand by the Regular" do
      game = create(:game)

      link(game, as: regular)

      expect(json.fetch("data")).to include("franchise_id" => franchise.franchise_id, "game_id" => game.game_id,
        "source" => "manual", "mainline" => false, "created_by" => regular.user_id)
      expect(json.dig("data", "created_at")).to be_present
    end

    it "marks a game Mainline, and takes the mark off again" do
      game = create(:game, title: "Final Fantasy VI")

      link(game, as: regular, mainline: true)
      expect(json.dig("data", "mainline")).to be(true)
      expect(titles(franchise_page.dig("games", "mainline"))).to eq([ "Final Fantasy VI" ])

      link(game, as: regular, mainline: false)
      expect(titles(franchise_page.dig("games", "mainline"))).to be_empty
      expect(titles(franchise_page.dig("games", "other"))).to eq([ "Final Fantasy VI" ])
    end

    it "marks a game Mainline in one Franchise and not in another" do
      game = create(:game, title: "Final Fantasy VII")
      compilation = create(:franchise, name: "Compilation of FFVII")

      link(game, as: regular, mainline: true)
      link(game, as: regular, mainline: false, into: compilation)

      expect(titles(franchise_page.dig("games", "mainline"))).to eq([ "Final Fantasy VII" ])
      expect(titles(franchise_page(of: compilation).dig("games", "other"))).to eq([ "Final Fantasy VII" ])
    end

    it "keeps an IGDB link's source and its Mainline mark when it is linked again without one" do
      game = create(:game)
      GamedbGameFranchise.create!(franchise: franchise, game: game, source: "igdb", mainline: true)

      link(game, as: regular)

      expect(json.fetch("data")).to include("source" => "igdb", "mainline" => true)
    end

    it "refuses a Mainline mark that isn't true or false" do
      link(create(:game), as: regular, mainline: "yes")

      expect(response).to have_http_status(:unprocessable_content)
      expect(json).to include("error" => "invalid_mainline")
    end

    it "404s for an unknown game or Franchise" do
      put "/api/v1/franchises/#{franchise.franchise_id}/games/999999999", headers: auth_headers_for(regular), as: :json
      expect(response).to have_http_status(:not_found)

      put "/api/v1/franchises/999999999/games/#{create(:game).game_id}", headers: auth_headers_for(regular), as: :json
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "unlinking a game" do
    it "lets a Regular remove a game from a Franchise" do
      kept = create(:game, title: "Final Fantasy IX")
      removed = create(:game, title: "Final Fantasy: All the Bravest")
      link(kept, as: regular)
      GamedbGameFranchise.create!(franchise: franchise, game: removed, source: "igdb")

      unlink(removed, as: regular)

      expect(response).to have_http_status(:no_content)
      expect(titles(franchise_page.dig("games", "other"))).to eq([ "Final Fantasy IX" ])
    end

    it "does nothing for a game that isn't linked" do
      unlink(create(:game), as: regular)

      expect(response).to have_http_status(:no_content)
      expect(GamedbFranchiseUnlink.count).to eq(0)
    end

    it "remembers the removal until the game is linked again by hand" do
      game = create(:game)
      GamedbGameFranchise.create!(franchise: franchise, game: game, source: "igdb")

      unlink(game, as: regular)
      expect(GamedbFranchiseUnlink.where(franchise_id: franchise.franchise_id, game_id: game.game_id))
        .to contain_exactly(have_attributes(unlinked_by: regular.user_id))

      link(game, as: regular)
      expect(GamedbFranchiseUnlink.where(franchise_id: franchise.franchise_id, game_id: game.game_id)).to be_empty
      expect(json.fetch("data")).to include("source" => "manual")
    end
  end

  describe "creating a Franchise" do
    it "lets a Regular create one IGDB doesn't have" do
      post "/api/v1/franchises", params: { data: { name: "  Soulslike  " } }, headers: auth_headers_for(regular),
        as: :json

      expect(response).to have_http_status(:created)
      expect(json.fetch("data")).to include("name" => "Soulslike", "igdb_franchise_id" => nil,
        "created_by" => regular.user_id)

      get "/api/v1/franchises", params: { q: "Soulslike" }, headers: auth_headers_for(member)
      expect(json.fetch("data").map { |f| f.fetch("name") }).to eq([ "Soulslike" ])
    end

    it "needs a name" do
      post "/api/v1/franchises", params: { data: { name: "  " } }, headers: auth_headers_for(regular), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "the Franchise page" do
    def in_franchise(game, mainline: false)
      GamedbGameFranchise.create!(franchise: franchise, game: game, source: "igdb", mainline: mainline)
      game
    end

    def game(title, year: nil, igdb_id: nil, parent: nil, parent_name: nil)
      create(:game, title: title, igdb_id: igdb_id, initial_release_date: year && Time.utc(year, 6, 1),
        parent_igdb_id: parent&.igdb_id || (parent_name && 999_999_001), parent_game_name: parent&.title || parent_name)
    end

    it "groups its games as Mainline, Other and Add-ons, each Add-on under its parent game" do
      ff14 = in_franchise(game("Final Fantasy XIV", year: 2013, igdb_id: 9_101), mainline: true)
      in_franchise(game("Final Fantasy X", year: 2001), mainline: true)
      in_franchise(game("Final Fantasy Tactics", year: 1997))
      in_franchise(game("Final Fantasy Unreleased"))
      in_franchise(game("Endwalker", year: 2021, parent: ff14), mainline: true)
      in_franchise(game("Heavensward", year: 2015, parent: ff14))
      outside = game("Dissidia", year: 2008, igdb_id: 9_102)
      in_franchise(game("Dissidia Costume Pack", year: 2009, parent: outside))
      in_franchise(game("Mystery DLC", year: 2010, parent_name: "Not In GameDB"))

      games = franchise_page.fetch("games")

      expect(titles(games.fetch("mainline"))).to eq([ "Final Fantasy X", "Final Fantasy XIV" ])
      expect(titles(games.fetch("other"))).to eq([ "Final Fantasy Tactics", "Final Fantasy Unreleased" ])
      expect(games.fetch("add_ons").map { |group| [ group["parent"]&.values_at("title", "in_franchise"),
                                                    titles(group.fetch("games")) ] }).to eq([
        [ [ "Dissidia", false ], [ "Dissidia Costume Pack" ] ],
        [ [ "Final Fantasy XIV", true ], [ "Heavensward", "Endwalker" ] ],
        [ nil, [ "Mystery DLC" ] ]
      ])
      expect(games.dig("add_ons", 2, "games", 0, "parent_game_name")).to eq("Not In GameDB")
    end

    it "gives each game its cover, release year, Mainline mark and source" do
      ff6 = in_franchise(game("Final Fantasy VI", year: 1994), mainline: true)
      image = create(:game_image, :primary, game: ff6)

      entry = franchise_page.dig("games", "mainline", 0)

      expect(entry).to include("game_id" => ff6.game_id, "title" => "Final Fantasy VI", "release_year" => 1994,
        "mainline" => true, "source" => "igdb", "parent_game_name" => nil)
      expect(entry.fetch("cover_url")).to eq(image.url)
    end

    it "says what the viewer may change" do
      expect(franchise_page(as: member).fetch("viewer")).to eq("can_edit" => false, "can_admin" => false)
      expect(franchise_page(as: regular).fetch("viewer")).to eq("can_edit" => true, "can_admin" => false)
      expect(franchise_page(as: create(:user, :admin)).fetch("viewer")).to eq("can_edit" => true, "can_admin" => true)
    end

    it "keeps the Franchise's own fields" do
      expect(franchise_page).to include("franchise_id" => franchise.franchise_id, "name" => "Final Fantasy",
        "igdb_franchise_id" => franchise.igdb_franchise_id)
    end
  end

  describe "a game's Franchises" do
    it "says whether the game is Mainline in each" do
      game = create(:game)
      spinoffs = create(:franchise, name: "Ivalice Alliance")
      link(game, as: regular, mainline: true)
      link(game, as: regular, into: spinoffs)

      get "/api/v1/games/#{game.game_id}/relations", headers: auth_headers_for(member)

      expect(json.dig("data", "franchises").map { |f| f.values_at("name", "mainline") })
        .to eq([ [ "Final Fantasy", true ], [ "Ivalice Alliance", false ] ])
    end
  end

  describe "an IGDB re-import" do
    let(:admin) { create(:user, :admin) }
    let(:igdb_client) { instance_double(Igdb::Client) }
    let(:igdb_franchises) { [] }
    let(:game) { create(:game, title: "Final Fantasy VII", igdb_id: SecureRandom.random_number(1_000_000_000)) }

    before do
      allow(Igdb::Client).to receive(:new).and_return(igdb_client)
      allow(Gamedb::IgdbImageImporter).to receive(:new)
        .and_return(instance_double(Gamedb::IgdbImageImporter, import!: []))
      allow(igdb_client).to receive(:game).with(game.igdb_id) do
        { igdb_id: game.igdb_id, name: game.title, slug: "ff7", summary: nil, url: nil, total_rating: nil,
          first_release_date: nil, parent_igdb_id: nil, parent_game_name: nil, collection: nil, genres: [],
          themes: [], perspectives: [], game_modes: [], engines: [], franchises: igdb_franchises, platforms: [],
          companies: [], release_dates: [] }
      end
    end

    def reimport
      post "/api/v1/games", params: { igdb_id: game.igdb_id }, headers: auth_headers_for(admin), as: :json
      expect(response).to have_http_status(:ok)
    end

    def igdb_ref(of) = { igdb_id: of.igdb_franchise_id, name: of.name }

    it "keeps a link made by hand that IGDB doesn't have" do
      link(game, as: regular)

      reimport

      expect(titles(franchise_page.dig("games", "other"))).to eq([ game.title ])
    end

    it "doesn't add back a game a person removed" do
      igdb_franchises << igdb_ref(franchise)
      GamedbGameFranchise.create!(franchise: franchise, game: game, source: "igdb")
      unlink(game, as: regular)

      reimport

      expect(franchise_page.fetch("games").values.flatten).to be_empty
    end

    it "keeps the Mainline mark on an IGDB link" do
      igdb_franchises << igdb_ref(franchise)
      reimport
      link(game, as: regular, mainline: true)

      reimport

      expect(titles(franchise_page.dig("games", "mainline"))).to eq([ game.title ])
    end

    it "still adds the IGDB links nobody removed, as IGDB's" do
      igdb_franchises << igdb_ref(franchise) << { igdb_id: 555_000_111, name: "Compilation of FFVII" }

      reimport

      links = GamedbGameFranchise.where(game_id: game.game_id).includes(:franchise)
      expect(links.map { |l| [ l.franchise.name, l.source, l.mainline ] })
        .to contain_exactly([ "Final Fantasy", "igdb", false ], [ "Compilation of FFVII", "igdb", false ])
    end
  end

  describe "who can change a Franchise" do
    let(:game) { create(:game) }

    it "refuses a member without the Regulars role every change" do
      link(game, as: member)
      expect(response).to have_http_status(:forbidden)
      expect(json).to eq("error" => "forbidden", "message" => "You need the Regulars role to change Franchises.")

      GamedbGameFranchise.create!(franchise: franchise, game: game, source: "igdb")
      unlink(game, as: member)
      expect(response).to have_http_status(:forbidden)

      post "/api/v1/franchises", params: { data: { name: "Mine" } }, headers: auth_headers_for(member), as: :json
      expect(response).to have_http_status(:forbidden)

      expect(titles(franchise_page.dig("games", "other"))).to eq([ game.title ])
      expect(GamedbFranchise.where(name: "Mine")).to be_empty
    end

    it "lets a Moderator without the Regulars role change one" do
      link(game, as: create(:user, role_moderator: true))

      expect(response).to have_http_status(:ok)
    end

    it "decides for the bot from the member it acts for" do
      put "/api/v1/franchises/#{franchise.franchise_id}/games/#{game.game_id}",
        params: { data: { acting_user_id: member.user_id } }, headers: service_headers, as: :json
      expect(response).to have_http_status(:forbidden)

      put "/api/v1/franchises/#{franchise.franchise_id}/games/#{game.game_id}",
        params: { data: { acting_user_id: regular.user_id } }, headers: service_headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "created_by")).to eq(regular.user_id)

      delete "/api/v1/franchises/#{franchise.franchise_id}/games/#{game.game_id}", headers: service_headers
      expect(response).to have_http_status(:bad_request)
      expect(json).to eq("error" => "acting_user_id required")

      delete "/api/v1/franchises/#{franchise.franchise_id}/games/#{game.game_id}?acting_user_id=#{regular.user_id}",
        headers: service_headers
      expect(response).to have_http_status(:no_content)
    end

    it "needs a signed-in caller" do
      put "/api/v1/franchises/#{franchise.franchise_id}/games/#{game.game_id}", as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
