# frozen_string_literal: true

require "rails_helper"

# Franchise suggestions for a game (spec api#487, ticket api#489). Game Edit
# offers up to three Franchises a game probably belongs to, each with why
# and the role it likely has there, to those who may change Franchises.
RSpec.describe "Franchise suggestions", type: :request do
  let(:regular) { create(:user, role_member: true, role_regular: true) }

  def suggestions_for(game, as: regular)
    get "/api/v1/games/#{game.game_id}/franchise_suggestions", headers: auth_headers_for(as)
    expect(response).to have_http_status(:ok)
    json.fetch("data")
  end

  def names(suggestions) = suggestions.map { |suggestion| suggestion.dig("franchise", "name") }

  it "suggests the Franchise its IGDB Series is named after" do
    series = create(:gamedb_collection, name: "Suikoden")
    franchise = create(:franchise, name: "Suikoden")
    game = create(:game, title: "Genso Suikogaiden", collection_id: series.collection_id)

    suggestion = suggestions_for(game).sole

    expect(suggestion.dig("franchise", "franchise_id")).to eq(franchise.franchise_id)
    expect(suggestion.fetch("reason")).to eq("series_name")
  end

  it "suggests the Franchise other games in its IGDB Series are linked to" do
    series = create(:gamedb_collection, name: "Wild Arms")
    franchise = create(:franchise, name: "Arms Collection")
    sibling = create(:game, title: "Wild Arms 2", collection_id: series.collection_id)
    GamedbGameFranchise.create!(franchise: franchise, game: sibling, source: "igdb")
    game = create(:game, title: "Wild Arms 3", collection_id: series.collection_id)

    suggestion = suggestions_for(game).sole

    expect(suggestion.dig("franchise", "franchise_id")).to eq(franchise.franchise_id)
    expect(suggestion).to include("reason" => "series_links", "series_games_linked" => 1)
  end

  it "suggests a Franchise whose name stands in its title as whole words" do
    franchise = create(:franchise, name: "Ys")
    create(:franchise, name: "Odyssey Saga")
    create(:franchise, name: "Lost Ody")
    game = create(:game, title: "Ys VIII: Lacrimosa of DANA")
    create(:game, title: "Lost Odyssey")

    suggestion = suggestions_for(game).sole

    expect(suggestion.dig("franchise", "franchise_id")).to eq(franchise.franchise_id)
    expect(suggestion.fetch("reason")).to eq("title_match")
  end

  it "does not match a name inside a longer word" do
    create(:franchise, name: "Ys")
    game = create(:game, title: "Odyssey of Ysland and Keys")

    expect(suggestions_for(game)).to be_empty
  end

  it "lists every reason a Franchise has, the strongest as its reason" do
    series = create(:gamedb_collection, name: "Tales of")
    franchise = create(:franchise, name: "Tales of")
    sibling = create(:game, title: "Tales of Symphonia", collection_id: series.collection_id)
    GamedbGameFranchise.create!(franchise: franchise, game: sibling, source: "igdb")
    game = create(:game, title: "Tales of Vesperia", collection_id: series.collection_id)

    suggestion = suggestions_for(game).sole

    expect(suggestion.fetch("reason")).to eq("series_name")
    expect(suggestion.fetch("reasons")).to eq(%w[series_name series_links title_match])
  end

  describe "the likely role" do
    it "guesses Mainline when most linked games in its Series are Mainline there" do
      series = create(:gamedb_collection, name: "Persona numbered")
      franchise = create(:franchise, name: "Megami Tensei")
      [ true, true, false ].each_with_index do |mainline, index|
        sibling = create(:game, title: "Sibling #{index}", collection_id: series.collection_id)
        GamedbGameFranchise.create!(franchise: franchise, game: sibling, source: "igdb", mainline: mainline)
      end
      game = create(:game, title: "Persona 5", collection_id: series.collection_id)

      expect(suggestions_for(game).sole.fetch("role")).to eq("mainline")
    end

    it "guesses a Spin-off when most linked games in its Series are not Mainline there" do
      series = create(:gamedb_collection, name: "Persona Dancing")
      franchise = create(:franchise, name: "Megami Tensei")
      [ true, false ].each_with_index do |mainline, index|
        sibling = create(:game, title: "Sibling #{index}", collection_id: series.collection_id)
        GamedbGameFranchise.create!(franchise: franchise, game: sibling, source: "igdb", mainline: mainline)
      end
      game = create(:game, title: "Persona 4: Dancing All Night", collection_id: series.collection_id)

      expect(suggestions_for(game).sole.fetch("role")).to eq("other")
    end

    it "guesses Mainline from a title that starts with the Franchise's name, and a Spin-off otherwise" do
      create(:franchise, name: "Final Fantasy")
      numbered = create(:game, title: "Final Fantasy IX")
      spin_off = create(:game, title: "Dissidia Final Fantasy")

      expect(suggestions_for(numbered).sole.fetch("role")).to eq("mainline")
      expect(suggestions_for(spin_off).sole.fetch("role")).to eq("other")
    end

    it "guesses an Add-on of its IGDB parent when the parent is in that Franchise" do
      franchise = create(:franchise, name: "Final Fantasy")
      parent = create(:game, title: "Final Fantasy XVI", igdb_id: SecureRandom.random_number(1_000_000_000))
      GamedbGameFranchise.create!(franchise: franchise, game: parent, source: "igdb", mainline: true)
      game = create(:game, title: "Final Fantasy XVI: The Rising Tide", parent_igdb_id: parent.igdb_id)

      expect(suggestions_for(game).sole).to include("role" => "add_on", "parent_game_id" => parent.game_id,
        "parent_title" => "Final Fantasy XVI")
    end

    it "guesses an Add-on for any game with a parent, naming the parent when it is in GameDB" do
      create(:franchise, name: "Final Fantasy")
      parent = create(:game, title: "Some Parent", igdb_id: SecureRandom.random_number(1_000_000_000))
      game = create(:game, title: "Final Fantasy Extra", parent_igdb_id: parent.igdb_id)

      expect(suggestions_for(game).sole).to include("role" => "add_on", "parent_game_id" => parent.game_id,
        "parent_title" => "Some Parent")
    end

    it "guesses an Add-on with no parent named when the parent isn't in GameDB" do
      create(:franchise, name: "Final Fantasy")
      game = create(:game, title: "Final Fantasy Extra", parent_igdb_id: 987_654_321)

      expect(suggestions_for(game).sole).to include("role" => "add_on", "parent_game_id" => nil,
        "parent_title" => nil)
    end
  end

  describe "what is left out" do
    it "leaves out Franchises the game is already linked to" do
      franchise = create(:franchise, name: "Chrono")
      game = create(:game, title: "Chrono Cross")
      GamedbGameFranchise.create!(franchise: franchise, game: game, source: "manual")

      expect(suggestions_for(game)).to be_empty
    end

    it "leaves out merged Franchises" do
      target = create(:franchise, name: "Kingdom Hearts")
      create(:franchise, name: "Kingdom", merged_into_id: target.franchise_id)
      create(:franchise, name: "KH Series", merged_into_id: target.franchise_id)
      series = create(:gamedb_collection, name: "KH Series")
      game = create(:game, title: "Kingdom Hearts II", collection_id: series.collection_id)

      expect(names(suggestions_for(game))).to eq([ "Kingdom Hearts" ])
    end

    it "leaves out a Franchise the game was unlinked from by hand" do
      franchise = create(:franchise, name: "Mana")
      game = create(:game, title: "Trials of Mana")
      GamedbFranchiseUnlink.create!(franchise: franchise, game: game)

      expect(suggestions_for(game)).to be_empty
    end

    it "does not count the game itself as a linked Series game" do
      series = create(:gamedb_collection, name: "Grandia set")
      franchise = create(:franchise, name: "Grandia")
      game = create(:game, title: "Grandia II", collection_id: series.collection_id)
      GamedbGameFranchise.create!(franchise: franchise, game: game, source: "igdb")

      expect(suggestions_for(game)).to be_empty
    end
  end

  describe "ordering and the cap" do
    it "puts a Series name first, then linked Series games, then title matches, at most three" do
      series = create(:gamedb_collection, name: "Xeno Saga Set")
      by_name = create(:franchise, name: "Xeno Saga Set")
      by_links = create(:franchise, name: "Monolith Soft")
      sibling = create(:game, title: "Sibling", collection_id: series.collection_id)
      GamedbGameFranchise.create!(franchise: by_links, game: sibling, source: "igdb")
      create(:franchise, name: "Xeno")
      create(:franchise, name: "Chronicles")
      create(:franchise, name: "Xenoblade Chronicles")
      game = create(:game, title: "Xenoblade Chronicles X", collection_id: series.collection_id)

      suggestions = suggestions_for(game)

      expect(names(suggestions)).to eq([ by_name.name, by_links.name, "Xenoblade Chronicles" ])
      expect(suggestions.map { |suggestion| suggestion.fetch("reason") }).to eq(%w[series_name series_links title_match])
    end

    it "orders by more linked Series games, then the longer name" do
      series = create(:gamedb_collection, name: "Some Series")
      few = create(:franchise, name: "A Few More Links")
      many = create(:franchise, name: "Many Links")
      2.times do |index|
        sibling = create(:game, title: "Sibling #{index}", collection_id: series.collection_id)
        GamedbGameFranchise.create!(franchise: many, game: sibling, source: "igdb")
        GamedbGameFranchise.create!(franchise: few, game: sibling, source: "igdb") if index.zero?
      end
      game = create(:game, title: "Shining Force III", collection_id: series.collection_id)
      create(:franchise, name: "Shining")
      create(:franchise, name: "Shining Force")

      expect(names(suggestions_for(game))).to eq([ "Many Links", "A Few More Links", "Shining Force" ])
    end
  end

  describe "who may read them" do
    it "refuses a member below Regular" do
      member = create(:user, role_member: true)
      game = create(:game)

      get "/api/v1/games/#{game.game_id}/franchise_suggestions", headers: auth_headers_for(member)

      expect(response).to have_http_status(:forbidden)
    end

    it "answers the bot for a Regular it names, and refuses it without one" do
      create(:franchise, name: "Breath of Fire")
      game = create(:game, title: "Breath of Fire IV")

      get "/api/v1/games/#{game.game_id}/franchise_suggestions", params: { acting_user_id: regular.user_id },
        headers: service_headers
      expect(response).to have_http_status(:ok)
      expect(names(json.fetch("data"))).to eq([ "Breath of Fire" ])

      get "/api/v1/games/#{game.game_id}/franchise_suggestions", headers: service_headers
      expect(response).to have_http_status(:bad_request)
    end

    it "is 404 for an unknown game" do
      get "/api/v1/games/0/franchise_suggestions", headers: auth_headers_for(regular)

      expect(response).to have_http_status(:not_found)
    end
  end
end
