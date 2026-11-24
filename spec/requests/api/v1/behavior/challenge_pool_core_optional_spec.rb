# frozen_string_literal: true

require "rails_helper"

# Core and Optional Games in Pools (spec api#442, ticket api#445; ADR 0014):
# sources only add Optional Games, a Run Finishes on every Core Game plus the
# Optional target, the Pool stays editable once Runs exist, a Core addition
# or a target raise DMs the members in a Run, and any member hosts a Slots or
# Pool Challenge.
RSpec.describe "api/v1/challenges Core and Optional Games", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:host) { create(:user, role_member: true) }
  let(:runner) { create(:user, role_member: true) }
  let(:moderator) { create(:user, role_member: true, role_moderator: true) }
  let(:franchise) { create(:franchise, name: "Final Fantasy") }
  let(:series) { create(:gamedb_collection, name: "Compilation of FFVII") }
  let!(:ff1) { create(:game, title: "Final Fantasy", initial_release_date: Time.utc(1987, 12, 18)) }
  let!(:ff6) { create(:game, title: "Final Fantasy VI", initial_release_date: Time.utc(1994, 4, 2)) }
  let!(:ff7) { create(:game, title: "Final Fantasy VII", initial_release_date: Time.utc(1997, 1, 31)) }
  let!(:ff11) { create(:game, title: "Final Fantasy XI", initial_release_date: Time.utc(2002, 5, 16)) }
  let!(:dlc) { create(:game, title: "Final Fantasy XI: Rise of the Zilart", parent_igdb_id: 11) }
  let!(:crisis_core) { create(:game, title: "Crisis Core", collection_id: series.collection_id) }
  let!(:tactics) { create(:game, title: "Final Fantasy Tactics") }

  # IGDB-era links have no known join time.
  before do
    [ ff1, ff6, ff7, ff11, dlc ].each { |game| GamedbGameFranchise.create!(game: game, franchise: franchise) }
    GamedbGameFranchise.where(franchise_id: franchise.franchise_id).update_all(created_at: nil)
  end

  # Mid-October 2026 in the club's time zone.
  around { |example| travel_to(Time.zone.parse("2026-10-15 12:00:00 -04:00")) { example.run } }

  def create_pool(as: host, **pool)
    post "/api/v1/challenges", headers: auth_headers_for(as), as: :json, params: { data: {
      name: "Fall of Final Fantasy", challenge_format: "pool", schedule: "always_open", pool: pool
    } }
  end

  def created_pool(**pool)
    create_pool(**pool)
    expect(response).to have_http_status(:created), response.body
    Challenge.find(json.dig("data", "id"))
  end

  def edit_pool(challenge, as: host, **data)
    patch "/api/v1/challenges/#{challenge.id}", params: { data: data }, headers: auth_headers_for(as), as: :json
  end

  def show(challenge, as: runner)
    get "/api/v1/challenges/#{challenge.id}", headers: auth_headers_for(as)
    json.dig("data", "pool")
  end

  def start_run(challenge, as: runner)
    post "/api/v1/challenges/#{challenge.id}/runs", headers: auth_headers_for(as), as: :json
    expect(response).to have_http_status(:created), response.body
    ChallengeRun.find(json.dig("data", "id"))
  end

  def clear(game, as: runner)
    post "/api/v1/users/#{as.user_id}/completions",
      params: { data: { gamedb_game_id: game.game_id, completion_type: "Main Story", completed_at: "2026-10-15" } },
      headers: auth_headers_for(as), as: :json
    expect(response).to have_http_status(:created), response.body
  end

  def progress(run)
    get "/api/v1/challenge_runs/#{run.id}", headers: auth_headers_for(runner)
    json.dig("data", "progress")
  end

  def titles(games) = games.map { |game| game.fetch("title") }

  describe "which games are in the Pool" do
    it "takes Core Games only from the core rows and feeds Optional from sources, leaving out Add-ons, " \
       "excluded and Core games" do
      challenge = created_pool(franchise_ids: [ franchise.franchise_id ], collection_ids: [ series.collection_id ],
        core_game_ids: [ ff1.game_id, ff6.game_id ], optional_game_ids: [ tactics.game_id ],
        excluded_game_ids: [ ff11.game_id ], optional_target: 1)

      pool = show(challenge)
      expect(titles(pool.fetch("core_games"))).to eq([ "Final Fantasy", "Final Fantasy VI" ])
      expect(pool.fetch("optional_games").map { |game| game.values_at("title", "source") }).to contain_exactly(
        [ "Final Fantasy VII", "franchise" ], [ "Crisis Core", "series" ], [ "Final Fantasy Tactics", "hand" ]
      )
      expect(titles(pool.fetch("excluded_games"))).to eq([ "Final Fantasy XI" ])
      expect(pool).to include("optional_target" => 1, "core_count" => 2, "optional_count" => 3, "game_count" => 5,
        "franchises" => [ { "franchise_id" => franchise.franchise_id, "name" => "Final Fantasy" } ],
        "collections" => [ { "collection_id" => series.collection_id, "name" => "Compilation of FFVII" } ])
      expect(pool.fetch("core_games").first).to include("game_id" => ff1.game_id, "cover_url" => nil)
    end

    it "lets the Host add an Add-on by hand" do
      challenge = created_pool(franchise_ids: [ franchise.franchise_id ], optional_game_ids: [ dlc.game_id ],
        optional_target: 1)

      expect(titles(show(challenge).fetch("optional_games"))).to include("Final Fantasy XI: Rise of the Zilart")
    end

    it "keeps a removed game out though its Franchise still has it" do
      challenge = created_pool(franchise_ids: [ franchise.franchise_id ], optional_target: 1)

      edit_pool(challenge, pool: { excluded_game_ids: [ ff7.game_id ] })

      expect(response).to have_http_status(:ok)
      expect(titles(show(challenge).fetch("optional_games"))).not_to include("Final Fantasy VII")
    end

    it "moves a game between Core and Optional in one edit" do
      challenge = created_pool(franchise_ids: [ franchise.franchise_id ], core_game_ids: [ ff1.game_id ])

      edit_pool(challenge, pool: { core_game_ids: [ ff7.game_id ], optional_game_ids: [ ff1.game_id ] })

      pool = show(challenge)
      expect(titles(pool.fetch("core_games"))).to eq([ "Final Fantasy VII" ])
      expect(pool.fetch("optional_games").find { |game| game["game_id"] == ff1.game_id }).to include("source" => "hand")
    end

    it "lists the Pool's games for the progress view, Core and Optional together" do
      challenge = created_pool(franchise_ids: [ franchise.franchise_id ], core_game_ids: [ tactics.game_id ],
        excluded_game_ids: [ ff11.game_id ])

      get "/api/v1/challenges/#{challenge.id}/pool_progress", headers: auth_headers_for(runner)

      expect(titles(json.fetch("data"))).to contain_exactly("Final Fantasy", "Final Fantasy VI", "Final Fantasy VII",
        "Final Fantasy Tactics")
    end

    it "previews a draft Pool's games the same way" do
      post "/api/v1/challenges/pool_preview", headers: auth_headers_for(host), as: :json, params: { data: {
        franchise_ids: [ franchise.franchise_id ], core_game_ids: [ tactics.game_id ], excluded_game_ids: [ ff1.game_id ]
      } }

      expect(response).to have_http_status(:ok)
      expect(titles(json.fetch("data"))).to contain_exactly("Final Fantasy VI", "Final Fantasy VII", "Final Fantasy XI",
        "Final Fantasy Tactics")
    end

    it "refuses a Pool with no Core Game and a target of 0, a target over the Optional Games, and a game in " \
       "two lists" do
      create_pool(franchise_ids: [ franchise.franchise_id ])
      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("message")).to include("at least one Core Game or an Optional target")

      create_pool(franchise_ids: [ franchise.franchise_id ], core_game_ids: [ ff1.game_id ], optional_target: 4)
      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("message")).to include("The Optional target (4) is more than the 3 Optional Games")

      create_pool(core_game_ids: [ ff1.game_id ], excluded_game_ids: [ ff1.game_id ])
      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("message")).to include("more than one of core, optional and excluded")

      create_pool(core_game_ids: [ ff1.game_id ], optional_target: -1)
      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("message")).to include("optional_target")
    end

    it "defaults the Optional target to 0" do
      challenge = created_pool(core_game_ids: [ ff1.game_id ])

      expect(show(challenge)).to include("optional_target" => 0, "optional_games" => [])
    end

    it "leaves the Optional Games out of lists, which carry the Core and excluded games" do
      created_pool(franchise_ids: [ franchise.franchise_id ], core_game_ids: [ ff1.game_id ])

      get "/api/v1/challenges", headers: auth_headers_for(runner)

      expect(json.dig("data", 0, "pool")).to include("optional_games" => nil, "optional_count" => nil,
        "core_count" => 1, "optional_target" => 0)
      expect(titles(json.dig("data", 0, "pool", "core_games"))).to eq([ "Final Fantasy" ])
    end
  end

  describe "new Optional Games" do
    it "marks a game new for 14 days after it joined, only when it joined after the Challenge was created" do
      challenge = created_pool(franchise_ids: [ franchise.franchise_id ], core_game_ids: [ ff1.game_id ])
      old_link = create(:game, title: "Final Fantasy Origins")
      GamedbGameFranchise.create!(game: old_link, franchise: franchise, created_at: 1.day.ago)

      travel 1.day
      ff16 = create(:game, title: "Final Fantasy XVI")
      GamedbGameFranchise.create!(game: ff16, franchise: franchise)
      edit_pool(challenge, pool: { optional_game_ids: [ tactics.game_id ] })

      newness = show(challenge).fetch("optional_games").to_h { |game| [ game["title"], game["new"] ] }
      expect(newness).to include("Final Fantasy XVI" => true, "Final Fantasy Tactics" => true,
        "Final Fantasy VII" => false, "Final Fantasy Origins" => false)

      travel 15.days
      expect(show(challenge).fetch("optional_games").pluck("new")).to all(be(false))
    end

    it "keeps the time a hand-added game joined when the Pool is edited again" do
      challenge = created_pool(core_game_ids: [ ff1.game_id ])
      travel 1.day
      edit_pool(challenge, pool: { optional_game_ids: [ tactics.game_id ] })
      travel 13.days

      edit_pool(challenge, pool: { optional_game_ids: [ tactics.game_id, ff7.game_id ] })
      travel 2.days

      newness = show(challenge).fetch("optional_games").to_h { |game| [ game["title"], game["new"] ] }
      expect(newness).to eq("Final Fantasy Tactics" => false, "Final Fantasy VII" => true)
    end
  end

  describe "Finishing a Run" do
    it "needs every Core Game Cleared when the target is 0" do
      challenge = created_pool(franchise_ids: [ franchise.franchise_id ], core_game_ids: [ ff1.game_id, ff6.game_id ])
      run = start_run(challenge)

      clear(ff1)
      clear(ff7)
      expect(progress(run)).to eq("in_progress" => 0, "cleared" => 2, "target" => 2,
        "core" => { "cleared" => 1, "total" => 2 }, "optional" => { "cleared" => 1, "target" => 0 })
      expect(run.reload.status).to eq("active")

      clear(ff6)
      expect(run.reload.status).to eq("finished")
    end

    it "needs every Core Game and the target of Optional Games" do
      challenge = created_pool(franchise_ids: [ franchise.franchise_id ], core_game_ids: [ ff1.game_id ],
        optional_target: 2)
      run = start_run(challenge)

      clear(ff1)
      clear(ff6)
      expect(run.reload.status).to eq("active")

      clear(ff7)
      expect(run.reload.status).to eq("finished")
      expect(progress(run)).to include("core" => { "cleared" => 1, "total" => 1 },
        "optional" => { "cleared" => 2, "target" => 2 })
    end

    it "keeps a Finished Run Finished when a Core Game is added later" do
      challenge = created_pool(core_game_ids: [ ff1.game_id ])
      run = start_run(challenge)
      clear(ff1)
      expect(run.reload.status).to eq("finished")

      edit_pool(challenge, pool: { core_game_ids: [ ff1.game_id, ff6.game_id ] })

      expect(response).to have_http_status(:ok)
      expect(run.reload.status).to eq("finished")
    end

    it "Finishes Runs that now meet the goal when a Core Game is removed" do
      challenge = created_pool(core_game_ids: [ ff1.game_id, ff6.game_id ])
      run = start_run(challenge)
      clear(ff1)
      expect(run.reload.status).to eq("active")

      expect { edit_pool(challenge, pool: { core_game_ids: [ ff1.game_id ] }) }
        .to change { BotJob.where(kind: "challenge_announce").count }.by(1)

      expect(run.reload.status).to eq("finished")
    end

    it "Finishes Runs that now meet the goal when the target is lowered" do
      challenge = created_pool(franchise_ids: [ franchise.franchise_id ], optional_target: 2)
      run = start_run(challenge)
      clear(ff7)

      edit_pool(challenge, pool: { optional_target: 1 })

      expect(run.reload.status).to eq("finished")
    end
  end

  describe "editing once Runs exist" do
    it "keeps the Pool's games, sources and target editable, but not the Format or schedule" do
      challenge = created_pool(core_game_ids: [ ff1.game_id ])
      start_run(challenge)

      edit_pool(challenge, pool: { franchise_ids: [ franchise.franchise_id ], core_game_ids: [ ff6.game_id ],
                                   optional_game_ids: [ tactics.game_id ], excluded_game_ids: [ ff7.game_id ],
                                   collection_ids: [ series.collection_id ], optional_target: 2 })
      expect(response).to have_http_status(:ok), response.body
      expect(json.dig("data", "pool")).to include("optional_target" => 2)

      edit_pool(challenge, schedule: "seasonal", season: { start: "06-21", end: "09-22" })
      expect(response).to have_http_status(:conflict)
      expect(json.fetch("fields")).to eq(%w[schedule season])

      edit_pool(challenge, challenge_format: "slots", slots: { first_year: 1990, last_year: 1999 })
      expect(response).to have_http_status(:conflict)
      expect(json.fetch("fields")).to include("challenge_format")
    end
  end

  describe "the pool_goal_changed DM" do
    let(:opted_out) { create(:user, role_member: true, challenge_dms: false) }
    let(:finisher) { create(:user, role_member: true) }
    let!(:challenge) do
      created_pool(franchise_ids: [ franchise.franchise_id ], core_game_ids: [ ff1.game_id ], optional_target: 1)
    end

    before do
      start_run(challenge)
      start_run(challenge, as: opted_out)
      start_run(challenge, as: finisher)
      clear(ff1, as: finisher)
      clear(ff7, as: finisher)
      expect(ChallengeRun.find_by!(user_id: finisher.user_id).status).to eq("finished")
    end

    def dms = BotJob.where(kind: "challenge_dm").where("payload->>'event' = 'pool_goal_changed'")

    it "goes once per save to opted-in members with an Active Run when Core Games are added, naming them" do
      expect { edit_pool(challenge, pool: { core_game_ids: [ ff1.game_id, ff6.game_id, tactics.game_id ] }) }
        .to change { dms.count }.by(1)

      payload = dms.last.payload
      expect(payload).to include("user_id" => runner.user_id, "feature_key" => "challenges",
        "optional_target" => nil)
      expect(payload.fetch("added_core_games").pluck("title")).to eq([ "Final Fantasy VI", "Final Fantasy Tactics" ])
      expect(payload.dig("challenge", "id")).to eq(challenge.id)
      expect(payload.dig("run", "user", "user_id")).to eq(runner.user_id)
      expect(payload.dig("run", "progress", "core")).to eq("cleared" => 0, "total" => 3)
    end

    it "goes when the target is raised, naming the old and new target" do
      expect { edit_pool(challenge, pool: { optional_target: 3 }) }.to change { dms.count }.by(1)

      expect(dms.last.payload).to include("added_core_games" => [], "optional_target" => { "from" => 1, "to" => 3 })
    end

    it "is not sent for Optional changes, a lowered target, a removed Core Game or a text edit" do
      expect do
        edit_pool(challenge, pool: { optional_game_ids: [ tactics.game_id ], excluded_game_ids: [ ff6.game_id ] })
        edit_pool(challenge, pool: { optional_target: 0 })
        edit_pool(challenge, name: "Autumn of Final Fantasy")
        edit_pool(challenge, pool: { core_game_ids: [ ff7.game_id ] })
        edit_pool(challenge, pool: { core_game_ids: [ ff7.game_id ] })
      end.to change { dms.count }.by(1)

      # Moving FF VII from Optional to Core adds a Core Game.
      expect(dms.last.payload.fetch("added_core_games").pluck("title")).to eq([ "Final Fantasy VII" ])
    end
  end

  describe "who hosts" do
    def create_slots(as:)
      post "/api/v1/challenges", headers: auth_headers_for(as), as: :json, params: { data: {
        name: "Birth Years", challenge_format: "slots", schedule: "always_open",
        slots: { first_year: 1990, last_year: 1999 }
      } }
    end

    def create_assignment(as:)
      post "/api/v1/challenges", headers: auth_headers_for(as), as: :json, params: { data: {
        name: "Secret Santa", challenge_format: "assignment", schedule: "always_open"
      } }
    end

    it "lets any member create a Slots or Pool Challenge" do
      create_pool(core_game_ids: [ ff1.game_id ])
      expect(response).to have_http_status(:created)

      create_slots(as: host)
      expect(response).to have_http_status(:created)
    end

    it "refuses an Assignment Challenge below Moderator" do
      regular = create(:user, role_member: true, role_regular: true)
      create_assignment(as: regular)

      expect(response).to have_http_status(:forbidden)
      expect(json.fetch("message")).to eq("Only Moderators and above can create an Assignment Challenge.")

      create_assignment(as: moderator)
      expect(response).to have_http_status(:created)
    end
  end
end
