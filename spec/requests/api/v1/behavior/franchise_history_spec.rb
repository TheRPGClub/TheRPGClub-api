# frozen_string_literal: true

require "rails_helper"

# Franchise history, undo, rename, merge and delete (spec api#442, ticket
# api#444). Every change to a Franchise is recorded; Regulars and above undo
# link, unlink, Mainline and rename changes. Admins and above rename, merge
# and delete Franchises, and those survive IGDB re-imports.
RSpec.describe "Franchise history and admin", type: :request do
  let(:member) { create(:user, role_member: true) }
  let(:regular) { create(:user, role_member: true, role_regular: true, username: "regular_one") }
  let(:admin) { create(:user, :admin) }
  let(:franchise) { create(:franchise, name: "Final Fantasy") }

  def link(game, as: regular, mainline: nil, into: franchise)
    data = mainline.nil? ? {} : { mainline: mainline }
    put "/api/v1/franchises/#{into.franchise_id}/games/#{game.game_id}", params: { data: data },
      headers: auth_headers_for(as), as: :json
  end

  def unlink(game, as: regular, from: franchise)
    delete "/api/v1/franchises/#{from.franchise_id}/games/#{game.game_id}", headers: auth_headers_for(as)
  end

  def rename(name, as: admin, of: franchise)
    patch "/api/v1/franchises/#{of.franchise_id}", params: { data: { name: name } },
      headers: auth_headers_for(as), as: :json
  end

  def merge(source, into:, as: admin)
    post "/api/v1/franchises/#{source.franchise_id}/merge", params: { data: { into_id: into.franchise_id } },
      headers: auth_headers_for(as), as: :json
  end

  def destroy(target = franchise, as: admin)
    delete "/api/v1/franchises/#{target.franchise_id}", headers: auth_headers_for(as)
  end

  def changes(of: franchise, as: regular, **query)
    get "/api/v1/franchises/#{of.franchise_id}/changes", params: query, headers: auth_headers_for(as)
    expect(response).to have_http_status(:ok)
    json.fetch("data")
  end

  def undo(change_id, as: regular)
    post "/api/v1/franchise_changes/#{change_id}/undo", headers: auth_headers_for(as), as: :json
  end

  def latest_change(of: franchise) = GamedbFranchiseChange.where(franchise_id: of.franchise_id).order(:id).last

  def link_of(game, into: franchise) = GamedbGameFranchise.find_by(franchise_id: into.franchise_id, game_id: game.game_id)

  describe "the history" do
    it "records every link, unlink and Mainline change, newest first, with who made it" do
      game = create(:game, title: "Final Fantasy VI")

      link(game, mainline: true)
      link(game, mainline: false)
      unlink(game)

      rows = changes
      expect(rows.map { |row| row.fetch("action") }).to eq(%w[unlink mainline_off mainline_on link])
      expect(rows.first).to include("franchise_id" => franchise.franchise_id, "game_id" => game.game_id,
        "game_title" => "Final Fantasy VI", "user_id" => regular.user_id, "username" => "regular_one",
        "before" => include("source" => "manual", "mainline" => false), "after" => nil, "undone_at" => nil,
        "can_undo" => true)
      expect(rows.last).to include("before" => nil, "after" => { "source" => "manual", "mainline" => false })
      expect(rows.first.fetch("created_at")).to be_present
    end

    it "records creating, renaming and merging a Franchise" do
      post "/api/v1/franchises", params: { data: { name: "Soulslike" } }, headers: auth_headers_for(regular),
        as: :json
      created = GamedbFranchise.find(json.dig("data", "franchise_id"))
      rename("Soulslikes", of: created)
      merge(create(:franchise, name: "Souls-like"), into: created)

      rows = changes(of: created)
      expect(rows.map { |row| row.fetch("action") }).to eq(%w[merge rename create])
      expect(rows.map { |row| row.fetch("can_undo") }).to eq([ false, true, false ])
      expect(rows[1]).to include("before" => { "name" => "Soulslike", "name_locked" => false },
        "after" => { "name" => "Soulslikes", "name_locked" => true }, "user_id" => admin.user_id)
      expect(rows[0].fetch("before")).to include("name" => "Souls-like")
    end

    it "pages" do
      3.times { link(create(:game)) }

      rows = changes(per: 2)

      expect(rows.size).to eq(2)
      expect(json.dig("meta", "count")).to eq(3)
    end

    it "is for Regulars and above" do
      get "/api/v1/franchises/#{franchise.franchise_id}/changes", headers: auth_headers_for(member)

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "undo" do
    let(:game) { create(:game, title: "Final Fantasy VII") }

    it "undoes a link" do
      link(game)

      undo(latest_change.id)

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("action" => "link", "undone_by" => regular.user_id, "can_undo" => false)
      expect(json.dig("data", "undone_at")).to be_present
      expect(link_of(game)).to be_nil
    end

    it "shows who undid a change in the history" do
      link(game)

      undo(latest_change.id, as: admin)

      expect(changes.first).to include("undone_by" => admin.user_id, "undone_by_username" => admin.username,
        "can_undo" => false)
      expect(changes.first.fetch("undone_at")).to be_present
    end

    it "undoes a link that replaced a removal, so the game stays removed from re-imports" do
      GamedbGameFranchise.create!(franchise: franchise, game: game, source: "igdb")
      unlink(game)
      link(game)

      undo(latest_change.id)

      expect(link_of(game)).to be_nil
      expect(GamedbFranchiseUnlink.where(franchise_id: franchise.franchise_id, game_id: game.game_id)).to exist
    end

    it "undoes an unlink, bringing the link back as it was" do
      GamedbGameFranchise.create!(franchise: franchise, game: game, source: "igdb", mainline: true)
      unlink(game)

      undo(latest_change.id)

      expect(response).to have_http_status(:ok)
      expect(link_of(game)).to have_attributes(source: "igdb", mainline: true)
      expect(GamedbFranchiseUnlink.where(franchise_id: franchise.franchise_id, game_id: game.game_id)).to be_empty
    end

    it "undoes a Mainline change" do
      link(game, mainline: true)

      undo(latest_change.id)

      expect(latest_change.action).to eq("mainline_on")
      expect(link_of(game).mainline).to be(false)
    end

    it "undoes a rename, unlocking the name again" do
      rename("FF")

      undo(latest_change.id)

      expect(response).to have_http_status(:ok)
      expect(franchise.reload).to have_attributes(name: "Final Fantasy", name_locked: false)
    end

    it "writes no new history row" do
      link(game)

      expect { undo(latest_change.id) }.not_to change(GamedbFranchiseChange, :count)
    end

    it "refuses a change already undone" do
      link(game)
      undo(latest_change.id)

      undo(latest_change.id)

      expect(response).to have_http_status(:conflict)
      expect(json).to include("error" => "already_undone")
    end

    it "refuses a change a later change to the same game has superseded" do
      link(game)
      first = latest_change
      link(game, mainline: true)

      undo(first.id)

      expect(response).to have_http_status(:conflict)
      expect(json).to include("error" => "superseded")
      expect(link_of(game)).to be_present
      expect(changes.first.fetch("can_undo")).to be(true)
      expect(changes.last.fetch("can_undo")).to be(false)
    end

    it "allows undoing in turn, newest first" do
      link(game)
      first = latest_change
      link(game, mainline: true)

      undo(latest_change.id)
      undo(first.id)

      expect(response).to have_http_status(:ok)
      expect(link_of(game)).to be_nil
    end

    it "isn't blocked by a later change to another game" do
      link(game)
      first = latest_change
      link(create(:game))

      undo(first.id)

      expect(response).to have_http_status(:ok)
    end

    it "refuses a rename a later rename has superseded" do
      rename("FF")
      first = latest_change
      rename("Final Fantasy Series")

      undo(first.id)

      expect(response).to have_http_status(:conflict)
      expect(json).to include("error" => "superseded")
    end

    it "refuses a change whose game was changed outside the history" do
      link(game)
      GamedbGameFranchise.where(franchise_id: franchise.franchise_id, game_id: game.game_id).delete_all

      undo(latest_change.id)

      expect(response).to have_http_status(:conflict)
      expect(json).to include("error" => "superseded")
    end

    it "can't undo creating, merging or deleting a Franchise" do
      post "/api/v1/franchises", params: { data: { name: "Soulslike" } }, headers: auth_headers_for(regular),
        as: :json
      created = GamedbFranchise.find(json.dig("data", "franchise_id"))
      undo(latest_change(of: created).id)
      expect(response).to have_http_status(:unprocessable_content)
      expect(json).to include("error" => "not_undoable")

      merge(create(:franchise), into: created)
      undo(latest_change(of: created).id, as: admin)
      expect(json).to include("error" => "not_undoable")

      destroy(created)
      undo(latest_change(of: created).id, as: admin)
      expect(json).to include("error" => "not_undoable")
    end

    it "refuses the changes of a Franchise merged away" do
      link(game)
      merge(franchise, into: create(:franchise))

      undo(latest_change.id)

      expect(response).to have_http_status(:conflict)
      expect(json).to include("error" => "superseded")
    end

    it "is for Regulars and above" do
      link(game)

      undo(latest_change.id, as: member)

      expect(response).to have_http_status(:forbidden)
      expect(link_of(game)).to be_present
    end

    it "404s for an unknown change" do
      undo(999_999_999)

      expect(response).to have_http_status(:not_found)
    end

    it "decides for the bot from the member it acts for" do
      link(game)

      post "/api/v1/franchise_changes/#{latest_change.id}/undo", params: { data: { acting_user_id: member.user_id } },
        headers: service_headers, as: :json
      expect(response).to have_http_status(:forbidden)

      post "/api/v1/franchise_changes/#{latest_change.id}/undo", params: { data: { acting_user_id: regular.user_id } },
        headers: service_headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "undone_by")).to eq(regular.user_id)
    end
  end

  describe "renaming" do
    it "lets an Admin rename a Franchise and locks the name" do
      rename("  FF  ")

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("name" => "FF", "name_locked" => true)
      expect(franchise.reload.name).to eq("FF")
    end

    it "needs a name" do
      rename(" ")

      expect(response).to have_http_status(:unprocessable_content)
      expect(franchise.reload.name).to eq("Final Fantasy")
    end
  end

  describe "merging" do
    let(:target) { create(:franchise, name: "Final Fantasy (series)") }

    it "moves the links, keeping a game Mainline if it was in either" do
      both = create(:game)
      only_source = create(:game)
      GamedbGameFranchise.create!(franchise: franchise, game: both, source: "igdb", mainline: true)
      GamedbGameFranchise.create!(franchise: target, game: both, source: "manual", mainline: false)
      GamedbGameFranchise.create!(franchise: franchise, game: only_source, source: "manual", mainline: false)

      merge(franchise, into: target)

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("franchise_id" => target.franchise_id)
      expect(link_of(both, into: target)).to have_attributes(mainline: true, source: "manual")
      expect(link_of(only_source, into: target)).to have_attributes(mainline: false, source: "manual")
      expect(GamedbGameFranchise.where(franchise_id: franchise.franchise_id)).to be_empty
      expect(franchise.reload.merged_into_id).to eq(target.franchise_id)
    end

    it "repoints Pool sources" do
      challenge = create(:challenge)
      both = create(:challenge)
      ChallengePoolFranchise.create!(challenge: challenge, franchise: franchise)
      ChallengePoolFranchise.create!(challenge: both, franchise: franchise)
      ChallengePoolFranchise.create!(challenge: both, franchise: target)

      merge(franchise, into: target)

      expect(ChallengePoolFranchise.where(franchise_id: franchise.franchise_id)).to be_empty
      expect(ChallengePoolFranchise.where(franchise_id: target.franchise_id).pluck(:challenge_id))
        .to contain_exactly(challenge.id, both.id)
    end

    it "keeps a removal, so re-imports don't add the game to the target" do
      game = create(:game)
      GamedbGameFranchise.create!(franchise: franchise, game: game, source: "igdb")
      unlink(game)

      merge(franchise, into: target)

      expect(GamedbFranchiseUnlink.where(franchise_id: target.franchise_id, game_id: game.game_id)).to exist
    end

    it "takes the merged Franchise off the list and search" do
      merge(franchise, into: target)

      get "/api/v1/franchises", params: { q: "Final Fantasy" }, headers: auth_headers_for(member)

      expect(json.fetch("data").map { |row| row.fetch("franchise_id") }).to eq([ target.franchise_id ])
    end

    it "still shows the merged Franchise, pointing at the target" do
      merge(franchise, into: target)

      get "/api/v1/franchises/#{franchise.franchise_id}", headers: auth_headers_for(member)

      expect(json.dig("data", "merged_into_id")).to eq(target.franchise_id)
    end

    it "refuses changes to a merged Franchise" do
      merge(franchise, into: target)

      link(create(:game))

      expect(response).to have_http_status(:unprocessable_content)
      expect(json).to include("error" => "franchise_merged")
    end

    it "refuses merging a Franchise into itself or into a merged one" do
      merge(franchise, into: franchise)
      expect(response).to have_http_status(:unprocessable_content)
      expect(json).to include("error" => "invalid_merge")

      other = create(:franchise)
      merge(other, into: target)
      merge(franchise, into: other)
      expect(response).to have_http_status(:unprocessable_content)
      expect(json).to include("error" => "franchise_merged")
    end

    it "points Franchises merged earlier at the new target" do
      older = create(:franchise)
      merge(older, into: franchise)

      merge(franchise, into: target)

      expect(older.reload.merged_into_id).to eq(target.franchise_id)
    end
  end

  describe "deleting" do
    it "removes the Franchise, its links and its Pool sources, and keeps its history" do
      game = create(:game)
      link(game)
      challenge = create(:challenge)
      ChallengePoolFranchise.create!(challenge: challenge, franchise: franchise)

      destroy

      expect(response).to have_http_status(:no_content)
      expect(GamedbFranchise.find_by(franchise_id: franchise.franchise_id)).to be_nil
      expect(GamedbGameFranchise.where(game_id: game.game_id)).to be_empty
      expect(ChallengePoolFranchise.where(challenge_id: challenge.id)).to be_empty
      expect(GamedbFranchiseChange.where(franchise_id: franchise.franchise_id).pluck(:action))
        .to contain_exactly("link", "delete")
    end
  end

  describe "an IGDB re-import" do
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

    def igdb_ref(of, name: of.name) = { igdb_id: of.igdb_franchise_id, name: name }

    it "keeps a renamed Franchise's name" do
      rename("FF")
      igdb_franchises << igdb_ref(franchise, name: "Final Fantasy")

      reimport

      expect(franchise.reload).to have_attributes(name: "FF", name_locked: true)
    end

    it "links a merged Franchise's games to the target" do
      target = create(:franchise)
      merge(franchise, into: target)
      igdb_franchises << igdb_ref(franchise)

      reimport

      expect(GamedbGameFranchise.where(game_id: game.game_id).pluck(:franchise_id)).to eq([ target.franchise_id ])
    end

    it "doesn't create a deleted Franchise again" do
      igdb_id = franchise.igdb_franchise_id
      destroy
      igdb_franchises << { igdb_id: igdb_id, name: "Final Fantasy" }

      reimport

      expect(GamedbFranchise.where(igdb_franchise_id: igdb_id)).to be_empty
      expect(GamedbGameFranchise.where(game_id: game.game_id)).to be_empty
    end
  end

  describe "who can rename, merge and delete" do
    it "refuses Regulars" do
      target = create(:franchise)

      rename("FF", as: regular)
      expect(response).to have_http_status(:forbidden)
      expect(json).to eq("error" => "forbidden",
        "message" => "You need to be an Admin to rename, merge or delete Franchises.")

      merge(franchise, into: target, as: regular)
      expect(response).to have_http_status(:forbidden)

      destroy(as: regular)
      expect(response).to have_http_status(:forbidden)

      expect(franchise.reload).to have_attributes(name: "Final Fantasy", merged_into_id: nil)
    end

    it "decides for the bot from the member it acts for" do
      patch "/api/v1/franchises/#{franchise.franchise_id}",
        params: { data: { name: "FF", acting_user_id: regular.user_id } }, headers: service_headers, as: :json
      expect(response).to have_http_status(:forbidden)

      delete "/api/v1/franchises/#{franchise.franchise_id}", headers: service_headers
      expect(response).to have_http_status(:bad_request)

      delete "/api/v1/franchises/#{franchise.franchise_id}?acting_user_id=#{admin.user_id}", headers: service_headers
      expect(response).to have_http_status(:no_content)
    end
  end
end
