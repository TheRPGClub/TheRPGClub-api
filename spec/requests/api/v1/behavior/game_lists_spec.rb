# frozen_string_literal: true

require "rails_helper"

# Game Lists (spec api#442, ticket api#446): named lists of GameDB games a
# member keeps, or the club owns, under /api/v1/game_lists.
RSpec.describe "api/v1/game_lists behavior", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:member) { create(:user, role_member: true, global_name: "Rhea") }
  let(:other) { create(:user, role_member: true) }
  let(:moderator) { create(:user, role_member: true, role_moderator: true) }
  let(:admin) { create(:user, role_member: true, role_admin: true) }

  def create_game_list(as:, **data)
    post "/api/v1/game_lists", params: { data: { name: "Soulslikes" }.merge(data) }, headers: auth_headers_for(as),
      as: :json
  end

  describe "creating and reading a list" do
    it "lets a member create a list they own, Members-visible and ranked by default" do
      create_game_list(as: member, description: "Hard and fair.")

      expect(response).to have_http_status(:created)
      expect(json.fetch("data")).to include(
        "name" => "Soulslikes", "description" => "Hard and fair.", "visibility" => "members", "sort" => "ranked",
        "club" => false, "entry_count" => 0, "entries" => [], "preview_games" => [],
        "taken_over_from" => nil, "taken_over_at" => nil,
        "viewer" => { "can_edit" => true, "can_delete" => true }
      )
      expect(json.dig("data", "owner")).to include("user_id" => member.user_id, "global_name" => "Rhea")

      get "/api/v1/game_lists/#{json.dig('data', 'id')}", headers: auth_headers_for(other)
      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "viewer")).to eq("can_edit" => false, "can_delete" => false)
    end

    it "needs a name of at most 100 characters and a description of at most 500" do
      create_game_list(as: member, name: "  ")
      expect(response).to have_http_status(:unprocessable_content)
      expect(json).to eq("error" => "invalid_game_list", "message" => "Name can't be blank")

      create_game_list(as: member, name: "a" * 101)
      expect(json.fetch("message")).to eq("Name is too long (maximum is 100 characters)")

      create_game_list(as: member, description: "a" * 501)
      expect(json.fetch("message")).to eq("Description is too long (maximum is 500 characters)")

      create_game_list(as: member, name: "  #{'a' * 100}  ", description: "a" * 500)
      expect(response).to have_http_status(:created)
      expect(json.dig("data", "name")).to eq("a" * 100)
    end

    it "refuses an unknown visibility or sort, and a field that isn't text" do
      create_game_list(as: member, visibility: "friends")
      expect(json).to eq("error" => "invalid_game_list", "message" => "Visibility must be one of members, private")

      create_game_list(as: member, sort: "random")
      expect(json.fetch("message")).to eq("Sort must be one of ranked, alphabetical, added")

      create_game_list(as: member, name: { "text" => "Souls" })
      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("message")).to eq("name must be text")
      expect(GameList.count).to eq(0)
    end

    it "refuses a signed-out visitor" do
      get "/api/v1/game_lists"
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "Private lists" do
    let!(:secret) { create(:game_list, owner: member, name: "Guilty pleasures", visibility: "private") }

    it "are read only by their owner, never by staff" do
      get "/api/v1/game_lists/#{secret.id}", headers: auth_headers_for(member)
      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "viewer")).to eq("can_edit" => true, "can_delete" => true)

      [ other, moderator, admin ].each do |user|
        get "/api/v1/game_lists/#{secret.id}", headers: auth_headers_for(user)
        expect(response).to have_http_status(:not_found)
      end
      get "/api/v1/game_lists/#{secret.id}", headers: auth_headers_for(other, is_dev: true)
      expect(response).to have_http_status(:not_found)
    end

    it "are edited and deleted only by their owner" do
      [ moderator, admin ].each do |user|
        patch "/api/v1/game_lists/#{secret.id}", params: { data: { name: "Mine now" } }, headers: auth_headers_for(user),
          as: :json
        expect(response).to have_http_status(:not_found)
        delete "/api/v1/game_lists/#{secret.id}", headers: auth_headers_for(user)
        expect(response).to have_http_status(:not_found)
      end

      patch "/api/v1/game_lists/#{secret.id}", params: { data: { name: "Comfort games" } },
        headers: auth_headers_for(member), as: :json
      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "name")).to eq("Comfort games")
    end

    it "are left out of every listing for others, and kept in the owner's" do
      get "/api/v1/game_lists", headers: auth_headers_for(admin)
      expect(json.fetch("data")).to be_empty
      get "/api/v1/users/#{member.user_id}/game_lists", headers: auth_headers_for(moderator)
      expect(json.fetch("data")).to be_empty

      get "/api/v1/game_lists", headers: auth_headers_for(member)
      expect(json.fetch("data").map { |list| list["id"] }).to eq([ secret.id ])
      get "/api/v1/users/#{member.user_id}/game_lists", headers: auth_headers_for(member)
      expect(json.fetch("data").map { |list| list["id"] }).to eq([ secret.id ])
    end

    it "can be made Members-visible and back by the owner, but not by a Moderator" do
      list = create(:game_list, owner: member)

      patch "/api/v1/game_lists/#{list.id}", params: { data: { visibility: "private" } },
        headers: auth_headers_for(moderator), as: :json
      expect(response).to have_http_status(:forbidden)
      expect(json.fetch("message")).to eq("Only its owner can change who sees this Game List.")

      patch "/api/v1/game_lists/#{list.id}", params: { data: { visibility: "private" } },
        headers: auth_headers_for(member), as: :json
      expect(json.dig("data", "visibility")).to eq("private")

      patch "/api/v1/game_lists/#{secret.id}", params: { data: { visibility: "members" } },
        headers: auth_headers_for(member), as: :json
      expect(json.dig("data", "visibility")).to eq("members")
      get "/api/v1/game_lists/#{secret.id}", headers: auth_headers_for(other)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "who may edit and delete a Members-visible list" do
    let!(:list) { create(:game_list, owner: member, name: "Top 10") }
    let(:path) { "/api/v1/game_lists/#{list.id}" }

    def rename(as:)
      patch path, params: { data: { name: "Top 10 of all time" } }, headers: auth_headers_for(as), as: :json
    end

    it "refuses another member" do
      rename(as: other)
      expect(response).to have_http_status(:forbidden)
      expect(json).to eq("error" => "forbidden", "message" => GameLists::Refusals::EDIT)

      delete path, headers: auth_headers_for(other)
      expect(response).to have_http_status(:forbidden)
      expect(json.fetch("message")).to eq(GameLists::Refusals::DELETE)
    end

    it "lets a Moderator fix and delete it, keeping its owner" do
      rename(as: moderator)
      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "owner", "user_id")).to eq(member.user_id)
      expect(json.dig("data", "viewer")).to eq("can_edit" => true, "can_delete" => true)

      delete path, headers: auth_headers_for(moderator)
      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to eq("id" => list.id, "deleted" => true)
    end

    it "lets the owner delete it, with its entries" do
      create(:game_list_entry, game_list: list)

      delete path, headers: auth_headers_for(member)
      expect(response).to have_http_status(:ok)
      expect(GameList.exists?(list.id)).to be(false)
      expect(GameListEntry.count).to eq(0)
    end
  end

  describe "club lists" do
    it "are created by Moderators and above, never Private" do
      create_game_list(as: member, club: true)
      expect(response).to have_http_status(:forbidden)
      expect(json.fetch("message")).to eq("Only Moderators and above can create a club Game List.")

      create_game_list(as: moderator, club: true, visibility: "private")
      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("message")).to eq("Visibility of a club list must be members")

      create_game_list(as: moderator, club: true, name: "Club favourites")
      expect(response).to have_http_status(:created)
      expect(json.fetch("data")).to include("club" => true, "owner" => nil,
        "viewer" => { "can_edit" => true, "can_delete" => false })
    end

    it "are edited by Moderators and deleted only by Admins and above" do
      club_list = create(:game_list, owner: nil)
      path = "/api/v1/game_lists/#{club_list.id}"

      patch path, params: { data: { name: "Renamed" } }, headers: auth_headers_for(member), as: :json
      expect(response).to have_http_status(:forbidden)
      patch path, params: { data: { name: "Renamed" } }, headers: auth_headers_for(moderator), as: :json
      expect(response).to have_http_status(:ok)
      patch path, params: { data: { visibility: "private" } }, headers: auth_headers_for(admin), as: :json
      expect(response).to have_http_status(:forbidden)

      delete path, headers: auth_headers_for(moderator)
      expect(response).to have_http_status(:forbidden)
      delete path, headers: auth_headers_for(member, is_dev: true)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "entries" do
    let!(:list) { create(:game_list, owner: member) }
    let(:nioh) { create(:game, title: "Nioh") }
    let(:wukong) { create(:game, title: "Black Myth: Wukong") }
    let(:lies) { create(:game, title: "Lies of P") }
    let(:path) { "/api/v1/game_lists/#{list.id}" }

    def add(game, as: member, note: nil)
      post "#{path}/entries/#{game.game_id}", params: { data: { note: note }.compact }, headers: auth_headers_for(as),
        as: :json
    end

    def ids_in_order(as: member)
      get path, headers: auth_headers_for(as)
      json.dig("data", "entries").map { |entry| entry["game_id"] }
    end

    it "adds games last in the ranked order, with an optional note" do
      add(nioh, note: "  Start here.  ")
      expect(response).to have_http_status(:created)
      expect(json.fetch("data")).to include("game_id" => nioh.game_id, "position" => 1, "note" => "Start here.")
      expect(json.dig("data", "game")).to include("game_id" => nioh.game_id, "title" => "Nioh")
      expect(json.dig("data", "added_at")).to be_present

      add(wukong)
      expect(json.fetch("data")).to include("position" => 2, "note" => nil)

      get path, headers: auth_headers_for(other)
      expect(json.fetch("data")).to include("entry_count" => 2)
      expect(json.dig("data", "entries").map { |entry| [ entry["game_id"], entry["position"] ] })
        .to eq([ [ nioh.game_id, 1 ], [ wukong.game_id, 2 ] ])
      expect(json.dig("data", "preview_games").map { |game| game["title"] }).to eq([ "Nioh", "Black Myth: Wukong" ])
    end

    it "holds a game at most once" do
      add(nioh)
      add(nioh)

      expect(response).to have_http_status(:conflict)
      expect(json).to eq("error" => "already_in_list", "message" => "Nioh is already in this list.")
    end

    it "is not found for a game GameDB doesn't have" do
      post "#{path}/entries/999999999", headers: auth_headers_for(member), as: :json
      expect(response).to have_http_status(:not_found)
    end

    it "holds at most 500 games" do
      games = create_list(:game, 2)
      GameListEntry.insert_all!(Array.new(499) do |index|
        { game_list_id: list.id, game_id: create(:game).game_id, position: index + 1, added_at: Time.current }
      end)

      add(games.first)
      expect(response).to have_http_status(:created)
      expect(json.dig("data", "position")).to eq(500)

      add(games.last)
      expect(response).to have_http_status(:unprocessable_content)
      expect(json).to eq("error" => "list_full", "message" => "A Game List holds at most 500 games.")
    end

    it "keeps notes to 280 characters, and a blank note removes it" do
      add(nioh, note: "a" * 281)
      expect(response).to have_http_status(:unprocessable_content)
      expect(json).to eq("error" => "invalid_game_list", "message" => "Note is too long (maximum is 280 characters)")

      add(nioh, note: "a" * 280)
      expect(response).to have_http_status(:created)

      patch "#{path}/entries/#{nioh.game_id}", params: { data: { note: "Short now." } }, headers: auth_headers_for(member),
        as: :json
      expect(json.dig("data", "note")).to eq("Short now.")

      patch "#{path}/entries/#{nioh.game_id}", params: { data: { note: " " } }, headers: auth_headers_for(member),
        as: :json
      expect(json.dig("data", "note")).to be_nil

      patch "#{path}/entries/#{nioh.game_id}", params: { data: { note: 7 } }, headers: auth_headers_for(member),
        as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("message")).to eq("note must be text")

      patch "#{path}/entries/#{wukong.game_id}", params: { data: { note: "Not there." } },
        headers: auth_headers_for(member), as: :json
      expect(response).to have_http_status(:not_found)
    end

    it "removes a game and closes the gap in the ranked order" do
      [ nioh, wukong, lies ].each { |game| add(game) }

      delete "#{path}/entries/#{wukong.game_id}", headers: auth_headers_for(member)
      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to eq("game_list_id" => list.id, "game_id" => wukong.game_id, "deleted" => true)

      get path, headers: auth_headers_for(member)
      expect(json.dig("data", "entries").map { |entry| [ entry["game_id"], entry["position"] ] })
        .to eq([ [ nioh.game_id, 1 ], [ lies.game_id, 2 ] ])

      add(wukong)
      expect(json.dig("data", "position")).to eq(3)
    end

    it "sets the ranked order, which must name every game once" do
      [ nioh, wukong, lies ].each { |game| add(game) }
      order = "#{path}/entries/order"

      put order, params: { data: { game_ids: [ lies.game_id, nioh.game_id, wukong.game_id ] } },
        headers: auth_headers_for(member), as: :json
      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "entries").map { |entry| [ entry["game_id"], entry["position"] ] })
        .to eq([ [ lies.game_id, 1 ], [ nioh.game_id, 2 ], [ wukong.game_id, 3 ] ])

      [ [ lies.game_id, nioh.game_id ], [ lies.game_id, nioh.game_id, nioh.game_id ],
        [ lies.game_id, nioh.game_id, 42 ], [ lies.game_id, nioh.game_id, "x" ] ].each do |game_ids|
        put order, params: { data: { game_ids: game_ids } }, headers: auth_headers_for(member), as: :json
        expect(response).to have_http_status(:unprocessable_content)
        expect(json).to eq("error" => "invalid_order",
          "message" => "game_ids must list every game of the list exactly once.")
      end
      expect(ids_in_order).to eq([ lies.game_id, nioh.game_id, wukong.game_id ])
    end

    it "shows the games by the list's sort, keeping the ranked order for later" do
      travel_to(3.days.ago) { add(lies) }
      travel_to(2.days.ago) { add(nioh) }
      add(wukong)

      patch path, params: { data: { sort: "alphabetical" } }, headers: auth_headers_for(member), as: :json
      expect(json.dig("data", "entries").map { |entry| entry.dig("game", "title") })
        .to eq([ "Black Myth: Wukong", "Lies of P", "Nioh" ])
      expect(json.dig("data", "preview_games").map { |game| game["title"] })
        .to eq([ "Black Myth: Wukong", "Lies of P", "Nioh" ])

      patch path, params: { data: { sort: "added" } }, headers: auth_headers_for(member), as: :json
      expect(json.dig("data", "entries").map { |entry| entry.dig("game", "title") })
        .to eq([ "Black Myth: Wukong", "Nioh", "Lies of P" ])
      get "/api/v1/game_lists", headers: auth_headers_for(member)
      expect(json.dig("data", 0, "preview_games").map { |game| game["title"] })
        .to eq([ "Black Myth: Wukong", "Nioh", "Lies of P" ])

      patch path, params: { data: { sort: "ranked" } }, headers: auth_headers_for(member), as: :json
      expect(json.dig("data", "entries").map { |entry| entry.dig("game", "title") })
        .to eq([ "Lies of P", "Nioh", "Black Myth: Wukong" ])
    end

    it "lets only those who can edit the list change its entries" do
      add(nioh)

      add(wukong, as: other)
      expect(response).to have_http_status(:forbidden)
      delete "#{path}/entries/#{nioh.game_id}", headers: auth_headers_for(other)
      expect(response).to have_http_status(:forbidden)
      put "#{path}/entries/order", params: { data: { game_ids: [ nioh.game_id ] } }, headers: auth_headers_for(other),
        as: :json
      expect(response).to have_http_status(:forbidden)

      add(wukong, as: moderator)
      expect(response).to have_http_status(:created)
    end

    it "moves the list up the index when its entries change" do
      newer = create(:game_list, owner: other)
      list.update_columns(updated_at: 1.day.ago)

      get "/api/v1/game_lists", headers: auth_headers_for(member)
      expect(json.fetch("data").map { |row| row["id"] }).to eq([ newer.id, list.id ])

      add(nioh)
      get "/api/v1/game_lists", headers: auth_headers_for(member)
      expect(json.fetch("data").map { |row| row["id"] }).to eq([ list.id, newer.id ])
    end
  end

  describe "browsing" do
    let(:elden) { create(:game, title: "Elden Ring") }
    let!(:club_list) { create(:game_list, owner: nil, name: "Club Soulslikes") }
    let!(:souls) { create(:game_list, owner: other, name: "Souls I love") }
    let!(:jrpgs) { create(:game_list, owner: member, name: "JRPGs to play") }
    let!(:hidden) { create(:game_list, owner: other, name: "Secret souls", visibility: "private") }

    def ids(params = {}, as: member)
      get "/api/v1/game_lists", params: params, headers: auth_headers_for(as)
      expect(response).to have_http_status(:ok)
      json.fetch("data").map { |list| list["id"] }
    end

    before do
      [ club_list, souls, hidden ].each { |list| create(:game_list_entry, game_list: list, game: elden, position: 1) }
      { club_list => 3, souls => 2, jrpgs => 1, hidden => 4 }.each { |list, days| list.update_columns(updated_at: days.days.ago) }
    end

    it "lists club lists first, then the most recently changed" do
      expect(ids).to eq([ club_list.id, jrpgs.id, souls.id ])
      expect(json.dig("meta", "count")).to eq(3)
    end

    it "searches by name, ignoring case" do
      expect(ids({ q: "SOULS" })).to eq([ club_list.id, souls.id ])
      expect(ids({ q: "%" })).to eq([])
    end

    it "searches by a game in the list" do
      expect(ids({ game_id: elden.game_id })).to eq([ club_list.id, souls.id ])
      expect(ids({ game_id: elden.game_id }, as: other)).to eq([ club_list.id, souls.id, hidden.id ])
    end

    it "keeps the club's lists or one member's" do
      expect(ids({ owner: "club" })).to eq([ club_list.id ])
      expect(ids({ owner: other.user_id })).to eq([ souls.id ])
      expect(ids({ owner: other.user_id }, as: other)).to eq([ souls.id, hidden.id ])
    end

    it "shows a member's lists on their profile" do
      get "/api/v1/users/#{other.user_id}/game_lists", headers: auth_headers_for(member)
      expect(json.fetch("data").map { |list| list["id"] }).to eq([ souls.id ])
      expect(json.dig("data", 0)).to include("entry_count" => 1, "owner" => include("user_id" => other.user_id))
      expect(json.dig("data", 0)).not_to have_key("entries")
    end

    it "shows a game's lists with how many there are" do
      get "/api/v1/games/#{elden.game_id}/game_lists", headers: auth_headers_for(member)
      expect(response).to have_http_status(:ok)
      expect(json.fetch("data").map { |list| list["name"] }).to eq([ "Club Soulslikes", "Souls I love" ])
      expect(json.dig("meta", "count")).to eq(2)

      get "/api/v1/games/#{elden.game_id}/game_lists", headers: auth_headers_for(other)
      expect(json.dig("meta", "count")).to eq(3)

      get "/api/v1/games/999999999/game_lists", headers: auth_headers_for(member)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "through the bot" do
    let!(:secret) { create(:game_list, owner: member, visibility: "private") }

    it "reads and writes for the member it names, from their stored roles" do
      get "/api/v1/game_lists/#{secret.id}", headers: service_headers
      expect(response).to have_http_status(:not_found)
      get "/api/v1/game_lists/#{secret.id}", params: { acting_user_id: member.user_id }, headers: service_headers
      expect(response).to have_http_status(:ok)

      post "/api/v1/game_lists", params: { data: { name: "From Discord" } }, headers: service_headers, as: :json
      expect(response).to have_http_status(:bad_request)
      post "/api/v1/game_lists", params: { data: { name: "From Discord", acting_user_id: "123" } },
        headers: service_headers, as: :json
      expect(response).to have_http_status(:bad_request)

      game = create(:game)
      post "/api/v1/game_lists/#{secret.id}/entries/#{game.game_id}", params: { data: { acting_user_id: other.user_id } },
        headers: service_headers, as: :json
      expect(response).to have_http_status(:not_found)
      post "/api/v1/game_lists/#{secret.id}/entries/#{game.game_id}", params: { data: { acting_user_id: member.user_id } },
        headers: service_headers, as: :json
      expect(response).to have_http_status(:created)

      post "/api/v1/game_lists", params: { data: { name: "From Discord", acting_user_id: member.user_id } },
        headers: service_headers, as: :json
      expect(response).to have_http_status(:created)
      expect(json.dig("data", "owner", "user_id")).to eq(member.user_id)

      delete "/api/v1/game_lists/#{secret.id}", headers: service_headers
      expect(response).to have_http_status(:bad_request)
      delete "/api/v1/game_lists/#{secret.id}", params: { acting_user_id: member.user_id }, headers: service_headers
      expect(response).to have_http_status(:ok)
    end
  end

  describe "the feature gate" do
    # Each call reads, writes and lists through every endpoint, on a list of its own.
    def every_endpoint(headers, data = {})
      owner = data[:acting_user_id] ? RpgClubUser.find(data[:acting_user_id]) : admin
      list = create(:game_list, owner: owner)
      game = create(:game)
      create(:game_list_entry, game_list: list, game: game, position: 1)
      path = "/api/v1/game_lists/#{list.id}"
      reads = data.slice(:acting_user_id)
      statuses = []
      get "/api/v1/game_lists", params: reads, headers: headers
      statuses << response.status
      get path, params: reads, headers: headers
      statuses << response.status
      get "/api/v1/users/#{owner.user_id}/game_lists", params: reads, headers: headers
      statuses << response.status
      get "/api/v1/games/#{game.game_id}/game_lists", params: reads, headers: headers
      statuses << response.status
      post "/api/v1/game_lists", params: { data: data.merge(name: "New") }, headers: headers, as: :json
      statuses << response.status
      patch path, params: { data: data.merge(name: "Edited") }, headers: headers, as: :json
      statuses << response.status
      post "#{path}/entries/#{create(:game).game_id}", params: { data: data }, headers: headers, as: :json
      statuses << response.status
      patch "#{path}/entries/#{game.game_id}", params: { data: data.merge(note: "Hi") }, headers: headers, as: :json
      statuses << response.status
      put "#{path}/entries/order", params: { data: data.merge(game_ids: list.entries.order(:position).pluck(:game_id)) },
        headers: headers, as: :json
      statuses << response.status
      delete "#{path}/entries/#{game.game_id}", params: reads, headers: headers
      statuses << response.status
      delete path, params: reads, headers: headers
      statuses << response.status
    end

    ok = [ 200, 200, 200, 200, 201, 200, 201, 200, 200, 200, 200 ]

    it "starts in Preview" do
      expect(Features.fetch("game_lists")).to have_attributes(name: "Game Lists", core: false)
      expect(PinnedPages.fetch("lists").feature).to eq("game_lists")
    end

    it "hides every endpoint from non-staff in Preview" do
      set_feature_flag("game_lists", "preview")

      expect(every_endpoint(auth_headers_for(member))).to all(eq(404))
    end

    it "answers staff in Preview" do
      set_feature_flag("game_lists", "preview")

      expect(every_endpoint(auth_headers_for(admin))).to eq(ok)
    end

    it "hides every endpoint from everyone when Off" do
      set_feature_flag("game_lists", "off")

      expect(every_endpoint(auth_headers_for(admin))).to all(eq(404))
    end

    it "lets the service token through, applying the Flag to the member it acts for" do
      set_feature_flag("game_lists", "preview")

      expect(every_endpoint(service_headers, acting_user_id: admin.user_id)).to eq(ok)

      statuses = every_endpoint(service_headers, acting_user_id: member.user_id)
      expect(statuses.first(4)).to eq([ 200, 200, 200, 200 ])
      expect(statuses.drop(4)).to all(eq(403))
    end
  end
end
