# frozen_string_literal: true

require "rails_helper"

# A hand-set Add-on parent (GLOSSARY.md "Add-on"). On the Franchise editor,
# Regulars and above make a game an Add-on of another game, or stop it being
# one, through the link endpoint's `parent_game_id`. The parent is locked
# against IGDB re-imports, recorded in the Franchise's history and undoable.
RSpec.describe "Franchise Add-on parent", type: :request do
  let(:member) { create(:user, role_member: true) }
  let(:regular) { create(:user, role_member: true, role_regular: true) }
  let(:admin) { create(:user, :admin) }
  let(:franchise) { create(:franchise, name: "Final Fantasy") }
  let(:ff14) { igdb_game("Final Fantasy XIV") }
  let(:endwalker) { igdb_game("Endwalker") }

  def igdb_game(title, **attributes)
    create(:game, title: title, igdb_id: SecureRandom.random_number(1_000_000_000), **attributes)
  end

  def link(game, as: regular, into: franchise, **data)
    put "/api/v1/franchises/#{into.franchise_id}/games/#{game.game_id}", params: { data: data },
      headers: auth_headers_for(as), as: :json
  end

  def franchise_page(of: franchise)
    get "/api/v1/franchises/#{of.franchise_id}", headers: auth_headers_for(member)
    expect(response).to have_http_status(:ok)
    json.dig("data", "games")
  end

  def titles(group) = group.map { |entry| entry.fetch("title") }

  def add_on_groups(games = franchise_page)
    games.fetch("add_ons").map { |group| [ group.dig("parent", "title"), titles(group.fetch("games")) ] }
  end

  def undo(change_id, as: regular)
    post "/api/v1/franchise_changes/#{change_id}/undo", headers: auth_headers_for(as), as: :json
  end

  def latest_change(of: franchise) = GamedbFranchiseChange.where(franchise_id: of.franchise_id).order(:id).last

  describe "setting a parent" do
    it "makes the game an Add-on of the parent, shown under it on the Franchise page" do
      link(ff14, mainline: true)

      link(endwalker, parent_game_id: ff14.game_id)

      expect(response).to have_http_status(:ok)
      games = franchise_page
      expect(titles(games.fetch("mainline"))).to eq([ "Final Fantasy XIV" ])
      expect(titles(games.fetch("other"))).to be_empty
      expect(add_on_groups(games)).to eq([ [ "Final Fantasy XIV", [ "Endwalker" ] ] ])
      expect(games.dig("add_ons", 0, "games", 0)).to include("parent_game_name" => "Final Fantasy XIV",
        "parent_locked" => true)
    end

    it "answers with the link and the game's parent" do
      link(endwalker, parent_game_id: ff14.game_id)

      expect(json.fetch("data")).to include("franchise_id" => franchise.franchise_id,
        "game_id" => endwalker.game_id, "source" => "manual", "mainline" => false,
        "parent_game_id" => ff14.game_id, "parent_igdb_id" => ff14.igdb_id,
        "parent_game_name" => "Final Fantasy XIV", "parent_locked" => true)
      expect(endwalker.reload).to have_attributes(parent_igdb_id: ff14.igdb_id,
        parent_game_name: "Final Fantasy XIV", parent_locked: true)
    end

    it "accepts the id as a string" do
      link(endwalker, parent_game_id: ff14.game_id.to_s)

      expect(json.dig("data", "parent_game_id")).to eq(ff14.game_id)
    end

    it "moves an Add-on to another parent" do
      dissidia = igdb_game("Dissidia")
      endwalker.update!(parent_igdb_id: dissidia.igdb_id, parent_game_name: "Dissidia")
      link(endwalker)

      link(endwalker, parent_game_id: ff14.game_id)

      expect(add_on_groups).to eq([ [ "Final Fantasy XIV", [ "Endwalker" ] ] ])
    end

    it "sets a parent and Mainline in one request, as a drag between groups does" do
      endwalker.update!(parent_igdb_id: ff14.igdb_id, parent_game_name: ff14.title)

      link(endwalker, parent_game_id: nil, mainline: true)

      expect(titles(franchise_page.fetch("mainline"))).to eq([ "Endwalker" ])
      expect(latest_change.action).to eq("mainline_on")
    end

    it "leaves the parent alone when parent_game_id isn't given" do
      endwalker.update!(parent_igdb_id: ff14.igdb_id, parent_game_name: ff14.title)

      link(endwalker, mainline: true)

      expect(json.fetch("data")).to include("parent_game_id" => ff14.game_id, "parent_locked" => false)
      expect(GamedbFranchiseChange.where(action: "parent")).to be_empty
    end

    it "touches the game so its cached relations refresh" do
      endwalker.update_columns(updated_at: 1.day.ago)

      expect { link(endwalker, parent_game_id: ff14.game_id) }.to(change { endwalker.reload.updated_at })
    end

    it "takes the game out of the Mainline set, so Conquests count without it" do
      link(ff14, mainline: true)
      link(endwalker, mainline: true)
      create(:completion, user: member, game: ff14)

      link(endwalker, parent_game_id: ff14.game_id)

      expect(UserFranchiseConquest.where(user_id: member.user_id, franchise_id: franchise.franchise_id)).to exist
    end
  end

  describe "clearing a parent" do
    before { endwalker.update!(parent_igdb_id: ff14.igdb_id, parent_game_name: ff14.title) }

    it "stops the game being an Add-on" do
      link(endwalker, parent_game_id: nil)

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("parent_game_id" => nil, "parent_igdb_id" => nil,
        "parent_game_name" => nil, "parent_locked" => true)
      games = franchise_page
      expect(titles(games.fetch("other"))).to eq([ "Endwalker" ])
      expect(games.fetch("add_ons")).to be_empty
    end

    it "records nothing for a game that already has that parent, set by hand" do
      link(endwalker, parent_game_id: nil)

      expect { link(endwalker, parent_game_id: nil) }.not_to(change { GamedbFranchiseChange.count })
      expect(response).to have_http_status(:ok)
    end
  end

  describe "refusals" do
    def expect_refusal(code)
      expect(response).to have_http_status(:unprocessable_content)
      expect(json).to include("error" => code)
      expect(json.fetch("message")).to be_present
    end

    it "refuses a game as its own parent" do
      link(ff14, parent_game_id: ff14.game_id)

      expect_refusal("parent_is_self")
    end

    it "refuses a parent with no IGDB id, without linking the game" do
      homebrew = create(:game, title: "Homebrew")

      link(endwalker, parent_game_id: homebrew.game_id)

      expect_refusal("parent_not_igdb")
      expect(GamedbGameFranchise.where(game_id: endwalker.game_id)).to be_empty
      expect(endwalker.reload).to have_attributes(parent_igdb_id: nil, parent_locked: false)
    end

    it "refuses an Add-on as the parent" do
      heavensward = igdb_game("Heavensward", parent_igdb_id: ff14.igdb_id, parent_game_name: ff14.title)

      link(endwalker, parent_game_id: heavensward.game_id)

      expect_refusal("parent_is_add_on")
    end

    it "refuses to make a game with Add-ons an Add-on" do
      endwalker.update!(parent_igdb_id: ff14.igdb_id, parent_game_name: ff14.title)

      link(ff14, parent_game_id: igdb_game("Dissidia").game_id)

      expect_refusal("game_has_add_ons")
    end

    it "refuses an unknown parent and a parent_game_id that isn't an id" do
      link(endwalker, parent_game_id: 999_999_999)
      expect_refusal("parent_not_found")

      link(endwalker, parent_game_id: "ff14")
      expect_refusal("invalid_parent")
    end
  end

  describe "who can set a parent" do
    it "refuses a member without the Regulars role" do
      link(endwalker, as: member, parent_game_id: ff14.game_id)

      expect(response).to have_http_status(:forbidden)
      expect(endwalker.reload.parent_igdb_id).to be_nil
    end

    it "lets the bot set it for a Regular it names" do
      put "/api/v1/franchises/#{franchise.franchise_id}/games/#{endwalker.game_id}",
        params: { data: { parent_game_id: ff14.game_id, acting_user_id: regular.user_id } },
        headers: service_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(latest_change.user_id).to eq(regular.user_id)
    end
  end

  describe "the history and undo" do
    it "records the change with the parent before and after" do
      dissidia = igdb_game("Dissidia")
      endwalker.update!(parent_igdb_id: dissidia.igdb_id, parent_game_name: "Dissidia")

      link(endwalker, parent_game_id: ff14.game_id)

      expect(latest_change).to have_attributes(action: "parent", game_id: endwalker.game_id,
        user_id: regular.user_id,
        before: { "parent_game_id" => dissidia.game_id, "parent_igdb_id" => dissidia.igdb_id,
                  "parent_game_name" => "Dissidia", "parent_locked" => false },
        after: { "parent_game_id" => ff14.game_id, "parent_igdb_id" => ff14.igdb_id,
                 "parent_game_name" => "Final Fantasy XIV", "parent_locked" => true })
      get "/api/v1/franchises/#{franchise.franchise_id}/changes", headers: auth_headers_for(regular)
      expect(json.dig("data", 0)).to include("action" => "parent", "game_title" => "Endwalker", "can_undo" => true)
    end

    it "undoes a parent change, putting back the old parent and its IGDB lock" do
      dissidia = igdb_game("Dissidia")
      endwalker.update!(parent_igdb_id: dissidia.igdb_id, parent_game_name: "Dissidia")
      link(endwalker, parent_game_id: ff14.game_id)

      undo(latest_change.id)

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("action" => "parent", "can_undo" => false)
      expect(endwalker.reload).to have_attributes(parent_igdb_id: dissidia.igdb_id, parent_game_name: "Dissidia",
        parent_locked: false)
      expect(add_on_groups).to eq([ [ "Dissidia", [ "Endwalker" ] ] ])
    end

    it "undoes clearing a parent" do
      endwalker.update!(parent_igdb_id: ff14.igdb_id, parent_game_name: ff14.title)
      link(endwalker, parent_game_id: nil)

      undo(latest_change.id)

      expect(endwalker.reload).to have_attributes(parent_igdb_id: ff14.igdb_id, parent_locked: false)
    end

    it "undoes a parent change made with a Mainline change, either first" do
      endwalker.update!(parent_igdb_id: ff14.igdb_id, parent_game_name: ff14.title)
      link(endwalker, parent_game_id: nil, mainline: true)
      parent_change, mainline_change = GamedbFranchiseChange.where(game_id: endwalker.game_id).order(:id).last(2)

      undo(parent_change.id)
      expect(response).to have_http_status(:ok)
      undo(mainline_change.id)
      expect(response).to have_http_status(:ok)

      expect(endwalker.reload.parent_igdb_id).to eq(ff14.igdb_id)
      expect(GamedbGameFranchise.find_by(game_id: endwalker.game_id).mainline).to be(false)
    end

    it "refuses to undo a parent change a later one replaced, even from another Franchise" do
      compilation = create(:franchise, name: "FFXIV Expansions")
      link(endwalker, parent_game_id: ff14.game_id)
      first = latest_change
      link(endwalker, into: compilation, parent_game_id: nil)

      undo(first.id)

      expect(response).to have_http_status(:conflict)
      expect(json).to include("error" => "superseded")
    end

    it "touches the game on undo" do
      link(endwalker, parent_game_id: ff14.game_id)
      endwalker.update_columns(updated_at: 1.day.ago)

      expect { undo(latest_change.id) }.to(change { endwalker.reload.updated_at })
    end
  end

  describe "an IGDB re-import" do
    let(:igdb_client) { instance_double(Igdb::Client) }
    let(:dissidia) { igdb_game("Dissidia") }

    before do
      allow(Igdb::Client).to receive(:new).and_return(igdb_client)
      allow(Gamedb::IgdbImageImporter).to receive(:new)
        .and_return(instance_double(Gamedb::IgdbImageImporter, import!: []))
      allow(igdb_client).to receive(:game).with(endwalker.igdb_id) do
        { igdb_id: endwalker.igdb_id, name: endwalker.title, slug: "endwalker", summary: nil, url: nil,
          total_rating: nil, first_release_date: nil, parent_igdb_id: dissidia.igdb_id,
          parent_game_name: "Dissidia", collection: nil, genres: [], themes: [], perspectives: [],
          game_modes: [], engines: [], franchises: [], platforms: [], companies: [], release_dates: [] }
      end
    end

    def reimport
      post "/api/v1/games", params: { igdb_id: endwalker.igdb_id }, headers: auth_headers_for(admin), as: :json
      expect(response).to have_http_status(:ok)
    end

    it "keeps a parent set by hand" do
      link(endwalker, parent_game_id: ff14.game_id)

      reimport

      expect(endwalker.reload).to have_attributes(parent_igdb_id: ff14.igdb_id,
        parent_game_name: "Final Fantasy XIV", parent_locked: true)
    end

    it "keeps a parent cleared by hand" do
      link(endwalker, parent_game_id: nil)

      reimport

      expect(endwalker.reload).to have_attributes(parent_igdb_id: nil, parent_game_name: nil)
    end

    it "still takes IGDB's parent for a game nobody set by hand" do
      reimport

      expect(endwalker.reload).to have_attributes(parent_igdb_id: dissidia.igdb_id, parent_game_name: "Dissidia")
    end
  end
end
