# frozen_string_literal: true

require "rails_helper"

# Game Lists feeding Pool Challenges (spec api#442, ticket api#448): a list
# starts a Pool Challenge with its games as Core Games and stays linked one
# way, so games added to the list arrive as Optional Games; removing a Core
# Game from the list leaves a list notice for the Host; `add_to_list` grows
# the list from the Challenge; and the club takes over a linked list its
# owner deletes or makes Private.
RSpec.describe "api/v1 Game Lists linked to Challenges", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:owner) { create(:user, role_member: true) }
  let(:other) { create(:user, role_member: true) }
  let(:moderator) { create(:user, role_member: true, role_moderator: true) }
  let(:admin) { create(:user, role_member: true, role_admin: true) }
  let!(:nioh) { create(:game, title: "Nioh", initial_release_date: Time.utc(2017, 2, 7)) }
  let!(:wo_long) { create(:game, title: "Wo Long", initial_release_date: Time.utc(2023, 3, 3)) }
  let!(:wukong) { create(:game, title: "Black Myth: Wukong", initial_release_date: Time.utc(2024, 8, 20)) }
  let!(:wuchang) { create(:game, title: "Wuchang: Fallen Feathers") }
  let!(:lies) { create(:game, title: "Lies of P") }
  let(:list) { list_of(owner, nioh, wo_long, wukong, name: "Soulslikes") }

  def list_of(owner, *games, name: "A list", visibility: "members")
    create(:game_list, owner: owner, name: name, visibility: visibility).tap do |list|
      games.each.with_index(1) { |game, place| create(:game_list_entry, game_list: list, game: game, position: place) }
    end
  end

  def create_from(list, as: owner, **data)
    pool = { game_list_id: list.id }.merge(data.delete(:pool) || {})
    post "/api/v1/challenges", headers: auth_headers_for(as), as: :json, params: { data: {
      name: "Souls Autumn", challenge_format: "pool", schedule: "always_open", pool: pool, **data
    } }
  end

  def created_from(list, **)
    create_from(list, **)
    expect(response).to have_http_status(:created), response.body
    Challenge.find(json.dig("data", "id"))
  end

  def pool(challenge, as: owner)
    get "/api/v1/challenges/#{challenge.id}", headers: auth_headers_for(as)
    expect(response).to have_http_status(:ok), response.body
    json.dig("data", "pool")
  end

  def ids(games) = games.map { |game| game.fetch("game_id") }

  def add_entry(list, game, as: owner)
    post "/api/v1/game_lists/#{list.id}/entries/#{game.game_id}", headers: auth_headers_for(as), as: :json
    expect(response).to have_http_status(:created), response.body
  end

  def remove_entry(list, game, as: owner)
    delete "/api/v1/game_lists/#{list.id}/entries/#{game.game_id}", headers: auth_headers_for(as)
    expect(response).to have_http_status(:ok), response.body
  end

  def edit(challenge, as: owner, **data)
    patch "/api/v1/challenges/#{challenge.id}", params: { data: data }, headers: auth_headers_for(as), as: :json
  end

  def notices(challenge, as: owner)
    get "/api/v1/challenges/#{challenge.id}", headers: auth_headers_for(as)
    json.dig("data", "list_notices")
  end

  def resolve(challenge, notice_id, action, as: owner)
    post "/api/v1/challenges/#{challenge.id}/list_notices/#{notice_id}/#{action}", headers: auth_headers_for(as),
      as: :json
  end

  def list_games(list) = GameListEntry.where(game_list_id: list.id).order(:position).pluck(:game_id)

  describe "starting a Challenge from a list" do
    it "copies the list's games in as Core Games and links the list" do
      challenge = created_from(list)

      current = json.dig("data", "pool")
      expect(ids(current.fetch("core_games"))).to eq([ nioh.game_id, wo_long.game_id, wukong.game_id ])
      expect(current.fetch("optional_games")).to eq([])
      expect(current.fetch("game_list")).to eq("id" => list.id, "name" => "Soulslikes", "visible" => true,
        "can_add" => true)
      expect(challenge.pool_game_list_id).to eq(list.id)
      expect(ChallengePoolGame.where(challenge_id: challenge.id).pluck(:inclusion).uniq).to eq([ "core" ])
    end

    it "keeps games the request puts in Optional or excludes, and takes extra Core Games" do
      created_from(list, pool: { optional_game_ids: [ wukong.game_id ], excluded_game_ids: [ wo_long.game_id ],
                                 core_game_ids: [ lies.game_id ] })

      current = json.dig("data", "pool")
      expect(ids(current.fetch("core_games"))).to contain_exactly(nioh.game_id, lies.game_id)
      expect(ids(current.fetch("optional_games"))).to eq([ wukong.game_id ])
      expect(ids(current.fetch("excluded_games"))).to eq([ wo_long.game_id ])
    end

    it "is only for the list's owner, for a Challenge they host" do
      create_from(list, as: other)
      expect(response).to have_http_status(:forbidden)
      expect(json.fetch("message")).to eq(Challenges::Refusals::LINK_LIST)

      create_from(list, as: moderator)
      expect(response).to have_http_status(:forbidden)

      owner.update!(role_moderator: true)
      create_from(list, hosted_by_club: true)
      expect(response).to have_http_status(:forbidden)
      expect(Challenge.count).to eq(0)
    end

    it "takes a club list only for a club-hosted Challenge, by staff" do
      club_list = list_of(nil, nioh, name: "Club picks")

      create_from(club_list, as: moderator)
      expect(response).to have_http_status(:forbidden)

      create_from(club_list, as: moderator, hosted_by_club: true)
      expect(response).to have_http_status(:created), response.body
      expect(json.dig("data", "pool", "game_list")).to include("id" => club_list.id, "can_add" => true)
    end

    it "refuses a list the member can't see, and linking on an edit" do
      create_from(list_of(other, nioh, visibility: "private"))
      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("message")).to eq("pool game_list_id must be a Game List you can see")

      challenge = created_from(list)
      edit(challenge, pool: { game_list_id: list_of(owner, lies).id })
      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("message")).to eq("pool game_list_id can only be set when the Challenge is created")
    end

    it "takes the owner's Private list, which other members see as not visible" do
      challenge = created_from(list_of(owner, nioh, visibility: "private", name: "Secret"))

      expect(pool(challenge, as: other).fetch("game_list")).to include("name" => "Secret", "visible" => false,
        "can_add" => false)
    end
  end

  describe "a linked list feeding the Pool" do
    let!(:challenge) { travel_to(10.days.ago) { created_from(list) } }

    it "brings games added to the list in as new Optional Games from the list" do
      add_entry(list, wuchang)

      optional = pool(challenge).fetch("optional_games")
      expect(optional).to contain_exactly(a_hash_including("game_id" => wuchang.game_id, "source" => "list",
        "new" => true))
    end

    it "leaves out Add-ons and excluded games, and drops an Optional Game removed from the list" do
      dlc = create(:game, title: "Nioh: Dragon of the North", parent_igdb_id: 1)
      add_entry(list, dlc)
      add_entry(list, wuchang)
      add_entry(list, lies)
      edit(challenge, pool: { excluded_game_ids: [ lies.game_id ] })
      expect(response).to have_http_status(:ok), response.body
      expect(ids(pool(challenge).fetch("optional_games"))).to eq([ wuchang.game_id ])

      remove_entry(list, wuchang)

      expect(pool(challenge).fetch("optional_games")).to eq([])
      expect(notices(challenge)).to eq([])
    end

    it "lists the Challenge's list games among its covers" do
      add_entry(list, wuchang)

      get "/api/v1/challenges", headers: auth_headers_for(other)
      found = json.fetch("data").find { |row| row["id"] == challenge.id }
      expect(ids(found.fetch("pool_games"))).to include(wuchang.game_id)
    end
  end

  describe "list notices" do
    let!(:challenge) { created_from(list) }

    it "opens a notice for the Host when a Core Game leaves the list, seen only by deciders" do
      remove_entry(list, wo_long)

      expect(notices(challenge)).to contain_exactly(a_hash_including("id" => Integer,
        "game" => a_hash_including("game_id" => wo_long.game_id, "title" => "Wo Long")))
      expect(notices(challenge, as: other)).to be_nil
      expect(notices(challenge, as: moderator).size).to eq(1)
      expect(ids(pool(challenge).fetch("core_games"))).to include(wo_long.game_id)
    end

    it "opens one when a Moderator removes the game from a member's list too" do
      remove_entry(list, wo_long, as: moderator)

      expect(notices(challenge).size).to eq(1)
    end

    it "is cleared by Keep, which leaves the game Core" do
      remove_entry(list, wo_long)

      resolve(challenge, notices(challenge).first.fetch("id"), "keep")

      expect(response).to have_http_status(:ok), response.body
      expect(json.dig("data", "list_notices")).to eq([])
      expect(ids(json.dig("data", "pool", "core_games"))).to include(wo_long.game_id)
    end

    it "is cleared by Remove, which takes the game out of the Challenge, excluding it if a source holds it" do
      franchise = create(:franchise)
      GamedbGameFranchise.create!(game: wo_long, franchise: franchise)
      edit(challenge, pool: { franchise_ids: [ franchise.franchise_id ] })
      remove_entry(list, wo_long)
      remove_entry(list, wukong)
      first, second = notices(challenge).sort_by { |notice| notice.dig("game", "title") }

      resolve(challenge, second.fetch("id"), "remove")
      expect(response).to have_http_status(:ok), response.body
      resolve(challenge, first.fetch("id"), "remove")

      current = json.dig("data", "pool")
      expect(ids(current.fetch("core_games"))).to eq([ nioh.game_id ])
      expect(ids(current.fetch("optional_games"))).to eq([])
      expect(ids(current.fetch("excluded_games"))).to eq([ wo_long.game_id ])
      expect(json.dig("data", "list_notices")).to eq([])
    end

    it "lets a Moderator clear it, but not other members" do
      remove_entry(list, wo_long)
      id = notices(challenge).first.fetch("id")

      resolve(challenge, id, "keep", as: other)
      expect(response).to have_http_status(:forbidden)

      resolve(challenge, id, "keep", as: moderator)
      expect(response).to have_http_status(:ok)
    end

    it "goes away when the game is back in the list or no longer Core" do
      remove_entry(list, wo_long)
      remove_entry(list, wukong)

      add_entry(list, wo_long)
      edit(challenge, pool: { core_game_ids: [ nioh.game_id, wo_long.game_id ] })

      expect(response).to have_http_status(:ok), response.body
      expect(notices(challenge)).to eq([])
    end

    it "404s for a notice of another Challenge" do
      remove_entry(list, wo_long)
      id = notices(challenge).first.fetch("id")
      mine = created_from(list_of(owner, lies))

      resolve(mine, id, "keep")

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "add_to_list" do
    let!(:challenge) { created_from(list) }

    it "adds the games a pool edit adds by hand to the linked list" do
      edit(challenge, add_to_list: true, pool: { core_game_ids: [ nioh.game_id, wo_long.game_id, wukong.game_id,
                                                                    wuchang.game_id ],
                                               optional_game_ids: [ lies.game_id ] })

      expect(response).to have_http_status(:ok), response.body
      expect(list_games(list)).to eq([ nioh, wo_long, wukong, wuchang, lies ].map(&:game_id))
    end

    it "leaves the list alone without it" do
      edit(challenge, pool: { optional_game_ids: [ lies.game_id ] })

      expect(list_games(list)).to eq([ nioh, wo_long, wukong ].map(&:game_id))
    end

    it "adds an accepted proposal's game to the linked list" do
      post "/api/v1/challenges/#{challenge.id}/pool_proposals", params: { data: { game_id: wuchang.game_id } },
        headers: auth_headers_for(other), as: :json
      id = json.dig("data", "id")

      post "/api/v1/challenges/#{challenge.id}/pool_proposals/#{id}/accept",
        params: { data: { as: "optional", add_to_list: true } }, headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:ok), response.body
      expect(list_games(list)).to include(wuchang.game_id)
      expect(pool(challenge).fetch("optional_games")).to contain_exactly(a_hash_including(
        "game_id" => wuchang.game_id, "source" => "hand"))
    end

    it "is refused to a Moderator editing a member's Challenge, who may still edit it without" do
      edit(challenge, as: moderator, add_to_list: true, pool: { optional_game_ids: [ lies.game_id ] })
      expect(response).to have_http_status(:forbidden)
      expect(json.fetch("message")).to eq(Challenges::Refusals::ADD_TO_LIST)
      expect(pool(challenge, as: moderator).fetch("game_list")).to include("can_add" => false)

      edit(challenge, as: moderator, pool: { optional_game_ids: [ lies.game_id ] })
      expect(response).to have_http_status(:ok)
      expect(list_games(list)).not_to include(lies.game_id)
    end

    it "is refused when no list is linked" do
      unlinked = create(:challenge, host: owner)

      edit(unlinked, add_to_list: true, pool: { optional_game_ids: [ lies.game_id ] })

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("message")).to eq("This Challenge has no linked Game List to add to")
    end
  end

  describe "the club taking over a linked list" do
    let!(:challenge) { created_from(list) }

    it "refuses to delete it without confirm, naming the Challenges" do
      delete "/api/v1/game_lists/#{list.id}", headers: auth_headers_for(owner)

      expect(response).to have_http_status(:conflict)
      expect(json).to include("error" => "list_feeds_challenges",
        "challenges" => [ { "id" => challenge.id, "name" => "Souls Autumn" } ])
      expect(json.fetch("message")).to include("the club will keep it")
      expect(GameList.find(list.id).owner_user_id).to eq(owner.user_id)
    end

    it "hands a deleted list to the club, still feeding the Challenge" do
      travel_to(Time.zone.parse("2026-11-20 10:00:00")) do
        delete "/api/v1/game_lists/#{list.id}", params: { confirm: true }, headers: auth_headers_for(owner)
      end

      expect(response).to have_http_status(:ok), response.body
      expect(json.fetch("data")).to eq("id" => list.id, "deleted" => true, "taken_over" => true)
      kept = GameList.find(list.id)
      expect(kept).to have_attributes(owner_user_id: nil, visibility: "members", taken_over_from_user_id: owner.user_id,
        taken_over_at: Time.zone.parse("2026-11-20 10:00:00"))
      expect(challenge.reload.pool_game_list_id).to eq(list.id)
      expect(pool(challenge).fetch("game_list")).to include("id" => list.id, "can_add" => false)
    end

    it "takes the confirm from the bot's query too" do
      delete "/api/v1/game_lists/#{list.id}", params: { acting_user_id: owner.user_id, confirm: "true" },
        headers: service_headers

      expect(response).to have_http_status(:ok), response.body
      expect(GameList.find(list.id).owner_user_id).to be_nil
    end

    it "makes a club copy when it goes Private, relinking the Challenge" do
      add_entry(list, wuchang)
      GameListEntry.where(game_list_id: list.id, game_id: nioh.game_id).update_all(note: "Start here.")

      patch "/api/v1/game_lists/#{list.id}", params: { data: { visibility: "private" } },
        headers: auth_headers_for(owner), as: :json
      expect(response).to have_http_status(:conflict)
      expect(json.fetch("error")).to eq("list_feeds_challenges")
      expect(list.reload.visibility).to eq("members")

      patch "/api/v1/game_lists/#{list.id}", params: { data: { visibility: "private", confirm: true } },
        headers: auth_headers_for(owner), as: :json
      expect(response).to have_http_status(:ok), response.body
      expect(json.dig("data", "visibility")).to eq("private")

      copy = GameList.find(challenge.reload.pool_game_list_id)
      expect(copy.id).not_to eq(list.id)
      expect(copy).to have_attributes(owner_user_id: nil, visibility: "members", name: "Soulslikes",
        taken_over_from_user_id: owner.user_id)
      expect(copy.taken_over_at).to be_present
      expect(list_games(copy)).to eq(list_games(list))
      expect(copy.entries.find_by(game_id: nioh.game_id).note).to eq("Start here.")
      expect(ids(pool(challenge).fetch("optional_games"))).to eq([ wuchang.game_id ])
    end

    it "asks nothing of a list that feeds no Challenge" do
      lonely = list_of(owner, lies)

      patch "/api/v1/game_lists/#{lonely.id}", params: { data: { visibility: "private" } },
        headers: auth_headers_for(owner), as: :json
      expect(response).to have_http_status(:ok)

      delete "/api/v1/game_lists/#{lonely.id}", headers: auth_headers_for(owner)
      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to eq("id" => lonely.id, "deleted" => true, "taken_over" => false)
      expect(GameList.exists?(lonely.id)).to be(false)
    end

    it "ends the link when an Admin deletes the club copy, keeping the Challenge's games" do
      add_entry(list, wuchang)
      delete "/api/v1/game_lists/#{list.id}", params: { confirm: true }, headers: auth_headers_for(owner)

      delete "/api/v1/game_lists/#{list.id}", headers: auth_headers_for(admin)
      expect(response).to have_http_status(:conflict)

      delete "/api/v1/game_lists/#{list.id}", params: { confirm: true }, headers: auth_headers_for(admin)
      expect(response).to have_http_status(:ok), response.body
      expect(json.dig("data", "taken_over")).to be(false)
      expect(GameList.exists?(list.id)).to be(false)

      current = pool(challenge)
      expect(current.fetch("game_list")).to be_nil
      expect(ids(current.fetch("core_games"))).to eq([ nioh, wo_long, wukong ].map(&:game_id))
      expect(current.fetch("optional_games")).to contain_exactly(a_hash_including("game_id" => wuchang.game_id,
        "source" => "hand"))
    end
  end

  describe "handing the Challenge to another Host" do
    it "ends the link, keeping the games and clearing its notices" do
      challenge = created_from(list)
      add_entry(list, wuchang)
      remove_entry(list, nioh)

      put "/api/v1/challenges/#{challenge.id}/host", params: { data: { host_user_id: other.user_id } },
        headers: auth_headers_for(moderator), as: :json

      expect(response).to have_http_status(:ok), response.body
      expect(challenge.reload.pool_game_list_id).to be_nil
      current = pool(challenge, as: other)
      expect(current.fetch("game_list")).to be_nil
      expect(ids(current.fetch("core_games"))).to eq([ nioh, wo_long, wukong ].map(&:game_id))
      expect(ids(current.fetch("optional_games"))).to eq([ wuchang.game_id ])
      expect(ChallengePoolListNotice.where(challenge_id: challenge.id)).to be_empty
    end
  end
end
