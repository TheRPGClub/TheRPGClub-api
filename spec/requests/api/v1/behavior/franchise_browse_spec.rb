# frozen_string_literal: true

require "rails_helper"

# The /franchises index read (spec api#487, ticket api#488): each current
# Franchise with its Mainline, Spin-off and Add-on counts, up to three
# covers, its release span, Club plays, and the viewer's Mainline progress
# when the `franchise_progress` Feature is open to them.
RSpec.describe "GET /api/v1/franchises/browse", type: :request do
  let(:member) { create(:user) }

  def game(title, year: nil, parent: nil, cover: true)
    record = create(:game, title: title, initial_release_date: year && Date.new(year, 6, 1),
      parent_igdb_id: parent&.igdb_id)
    create(:game_image, :primary, game: record) if cover
    record
  end

  def link(franchise, game, mainline: false)
    GamedbGameFranchise.create!(franchise: franchise, game: game, source: "igdb", mainline: mainline)
  end

  def browse(as: member, **params)
    get "/api/v1/franchises/browse", params: params, headers: auth_headers_for(as)
    expect(response).to have_http_status(:ok)
    json
  end

  def names(body) = body.fetch("data").map { |row| row.fetch("name") }

  describe "a Franchise's row" do
    let(:franchise) { create(:franchise, name: "Final Fantasy") }
    let!(:ff1) { link(franchise, game("Final Fantasy", year: 1987), mainline: true).game }
    let!(:ff7) { link(franchise, game("Final Fantasy VII", year: 1997), mainline: true).game }
    let!(:tactics) { link(franchise, game("Final Fantasy Tactics", year: 1998)).game }

    before do
      ff7.update!(igdb_id: 427)
      link(franchise, game("Final Fantasy VII DLC", year: 2001, parent: ff7), mainline: true)
      link(franchise, game("Final Fantasy XV", year: 2016, cover: false), mainline: true)
    end

    it "counts Mainline, Spin-offs and Add-ons, and spans the release years" do
      row = browse.fetch("data").sole

      expect(row).to include("franchise_id" => franchise.franchise_id, "name" => "Final Fantasy",
        "mainline_count" => 3, "spin_off_count" => 1, "add_on_count" => 1, "games_count" => 5,
        "first_year" => 1987, "latest_year" => 2016)
    end

    it "gives up to three covers, newest Mainline with a cover first, then Spin-offs" do
      covers = browse.fetch("data").sole.fetch("covers")

      expect(covers.pluck("game_id")).to eq([ ff7.game_id, ff1.game_id, tactics.game_id ])
      expect(covers.first).to include("title" => "Final Fantasy VII", "cover_url" => be_present)
    end
  end

  describe "listing" do
    let!(:zelda) { create(:franchise, name: "Zelda") }
    let!(:atelier) { create(:franchise, name: "Atelier") }
    let!(:mana) { create(:franchise, name: "Mana") }
    let!(:empty) { create(:franchise, name: "Abandoned") }
    let!(:numbered) { create(:franchise, name: "8-Bit Saga") }

    before do
      link(zelda, game("Zelda 1", year: 1986), mainline: true)
      link(numbered, game("8-Bit Saga", year: 2020))
      2.times { |n| link(atelier, game("Atelier #{n}", year: 1997 + n)) }
      3.times { |n| link(mana, game("Mana #{n}", year: 1991 + n)) }
    end

    it "sorts A to Z by default, empty Franchises last" do
      expect(names(browse)).to eq([ "8-Bit Saga", "Atelier", "Mana", "Zelda", "Abandoned" ])
    end

    it "sorts by most games, empty Franchises last" do
      expect(names(browse(sort: "games"))).to eq([ "Mana", "Atelier", "8-Bit Saga", "Zelda", "Abandoned" ])
    end

    it "sorts by Club plays: Now Playing plus Completions in the last 90 days" do
      zelda_game = zelda.games.first
      create(:now_playing_entry, user: member, game: zelda_game)
      create(:completion, user: create(:user), game: zelda_game, completed_at: 10.days.ago)
      create(:completion, user: member, game: atelier.games.first, completed_at: 5.days.ago)
      create(:completion, user: create(:user), game: mana.games.first, completed_at: 120.days.ago)

      data = browse(sort: "plays").fetch("data")

      expect(data.pluck("name")).to eq([ "Zelda", "Atelier", "Mana", "8-Bit Saga", "Abandoned" ])
      expect(data.pluck("club_plays")).to eq([ 2, 1, 0, 0, 0 ])
    end

    it "searches names with q" do
      expect(names(browse(q: "ATEL"))).to eq([ "Atelier" ])
    end

    it "filters by starting letter, and # for names that don't start with one" do
      expect(names(browse(letter: "a"))).to eq([ "Atelier", "Abandoned" ])
      expect(names(browse(letter: "#"))).to eq([ "8-Bit Saga" ])
    end

    it "pages" do
      body = browse(per: 2, page: 2)

      expect(names(body)).to eq([ "Mana", "Zelda" ])
      expect(body.fetch("meta")).to include("page" => 2, "pages" => 3, "count" => 5, "per" => 2)
    end

    it "leaves out merged Franchises" do
      create(:franchise, name: "Mana Old", merged_into_id: mana.franchise_id)

      expect(names(browse(q: "mana"))).to eq([ "Mana" ])
    end

    it "gives an empty Franchise zero counts, no years and no covers" do
      expect(browse(q: "Abandoned").fetch("data").sole).to include("games_count" => 0, "mainline_count" => 0,
        "spin_off_count" => 0, "add_on_count" => 0, "first_year" => nil, "latest_year" => nil, "covers" => [])
    end

    it "refuses an unknown sort or letter" do
      get "/api/v1/franchises/browse", params: { sort: "newest" }, headers: auth_headers_for(member)
      expect(response).to have_http_status(:unprocessable_content)
      expect(json).to include("error" => "invalid_sort")

      get "/api/v1/franchises/browse", params: { letter: "ab" }, headers: auth_headers_for(member)
      expect(response).to have_http_status(:unprocessable_content)
      expect(json).to include("error" => "invalid_letter")
    end

    it "reads a page in a bounded number of queries, however many Franchises it holds" do
      count_queries = lambda do
        queries = []
        callback = ->(*, payload) { queries << payload[:sql] unless payload[:name] == "SCHEMA" }
        ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { browse(sort: "plays") }
        queries.size
      end
      count_queries.call # warms the per-process caches (Feature states, session)
      few = count_queries.call

      4.times do |n|
        franchise = create(:franchise, name: "More #{n}")
        2.times { |m| link(franchise, game("More #{n}.#{m}", year: 2000 + m), mainline: m.zero?) }
      end

      expect(count_queries.call).to eq(few)
    end

    it "requires a session" do
      get "/api/v1/franchises/browse"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "the viewer's Mainline progress" do
    let(:franchise) { create(:franchise, name: "Dragon Quest") }

    before do
      dq1 = link(franchise, game("Dragon Quest", year: 1986), mainline: true).game
      link(franchise, game("Dragon Quest II", year: 1987), mainline: true)
      link(franchise, game("Dragon Quest Builders", year: 2016))
      create(:completion, user: member, game: dq1)
      create(:completion, user: create(:user), game: dq1)
      create(:franchise, name: "Dragon Quest Monsters")
    end

    it "gives done and total Mainline games when Franchise Progress is open" do
      data = browse(q: "dragon").fetch("data")

      expect(data.map { |row| row.fetch("progress") }).to eq([
        { "done" => 1, "total" => 2 }, { "done" => 0, "total" => 0 }
      ])
    end

    it "leaves progress out when the Feature isn't open to the viewer" do
      set_feature_flag("franchise_progress", "preview")

      expect(browse(q: "dragon").fetch("data")).to all(satisfy { |row| !row.key?("progress") })
      expect(browse(q: "dragon", as: create(:user, role_admin: true)).fetch("data").first)
        .to include("progress" => { "done" => 0, "total" => 2 })
    end

    it "leaves progress out for the bot, which has no viewer" do
      get "/api/v1/franchises/browse", params: { q: "dragon" }, headers: service_headers

      expect(json.fetch("data")).to all(satisfy { |row| !row.key?("progress") })
    end
  end
end
