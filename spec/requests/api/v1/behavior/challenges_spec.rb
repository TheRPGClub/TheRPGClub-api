# frozen_string_literal: true

require "rails_helper"

# Challenges (spec #376, ticket #377): creating Pool Challenges, reading them,
# and who may change them.
RSpec.describe "api/v1/challenges behavior", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:regular) { create(:user, role_member: true, role_regular: true) }
  let(:member) { create(:user, role_member: true) }
  let(:moderator) { create(:user, role_member: true, role_moderator: true) }
  let(:franchise) { create(:franchise, name: "Final Fantasy") }
  let!(:ff7) { create(:game, title: "Final Fantasy VII") }

  before { GamedbGameFranchise.create!(game: ff7, franchise: franchise) }

  def pool_challenge(**overrides)
    {
      name: "Fall of Final Fantasy", description: "Play Final Fantasy through the autumn.",
      challenge_format: "pool", schedule: "always_open",
      pool: { franchise_ids: [ franchise.franchise_id ], target: 2 }
    }.merge(overrides)
  end

  def create_challenge(as:, **overrides)
    post "/api/v1/challenges", params: { data: pool_challenge(**overrides) }, headers: auth_headers_for(as), as: :json
  end

  # Mid-October, outside a summer Season and inside an autumn one.
  around { |example| travel_to(Time.zone.parse("2026-10-15 12:00:00 -04:00")) { example.run } }

  describe "creating a Pool Challenge" do
    it "lets a Regular create one and become its Host" do
      create_challenge(as: regular)

      expect(response).to have_http_status(:created)
      expect(json.fetch("data")).to include(
        "name" => "Fall of Final Fantasy", "description" => "Play Final Fantasy through the autumn.",
        "challenge_format" => "pool", "hosted_by_club" => false, "schedule" => "always_open", "ends_on" => nil,
        "season" => nil, "open" => true, "hidden" => false, "created_by" => regular.user_id, "run_count" => 0
      )
      expect(json.dig("data", "host")).to include("user_id" => regular.user_id, "username" => regular.username)
      expect(json.dig("data", "pool")).to include(
        "target" => 2, "game_count" => 1,
        "franchises" => [ { "franchise_id" => franchise.franchise_id, "name" => "Final Fantasy" } ]
      )
      expect(json.dig("meta", "warnings")).to eq([])
    end

    it "tells a member without the Regulars role that they need it" do
      create_challenge(as: member)

      expect(response).to have_http_status(:forbidden)
      expect(json.fetch("message")).to eq("You need the Regulars role to create a Challenge.")
    end

    it "lets Moderators create one without the Regulars role" do
      create_challenge(as: moderator)

      expect(response).to have_http_status(:created)
    end

    it "lets a Moderator host one for the club, but not a Regular" do
      create_challenge(as: moderator, hosted_by_club: true)

      expect(response).to have_http_status(:created)
      expect(json.fetch("data")).to include("hosted_by_club" => true, "host" => nil)

      create_challenge(as: regular, hosted_by_club: true)

      expect(response).to have_http_status(:forbidden)
      expect(json.fetch("message")).to include("hosted by the club")
    end

    it "creates for the member the bot names, from their stored roles" do
      post "/api/v1/challenges", params: { data: pool_challenge(acting_user_id: regular.user_id) },
        headers: service_headers, as: :json

      expect(response).to have_http_status(:created)
      expect(json.dig("data", "host", "user_id")).to eq(regular.user_id)

      post "/api/v1/challenges", params: { data: pool_challenge(acting_user_id: member.user_id) },
        headers: service_headers, as: :json
      expect(response).to have_http_status(:forbidden)

      post "/api/v1/challenges", params: { data: pool_challenge }, headers: service_headers, as: :json
      expect(response).to have_http_status(:bad_request)
    end

    it "succeeds with a warning when another Challenge has the same name" do
      existing = create(:challenge, name: "fall of final fantasy")

      create_challenge(as: regular)

      expect(response).to have_http_status(:created)
      expect(json.dig("meta", "warnings")).to contain_exactly(
        a_hash_including("code" => "duplicate_name", "challenge_ids" => [ existing.id ])
      )
    end

    it "queues a challenge_announce bot job carrying the new Challenge" do
      expect { create_challenge(as: regular) }.to change { BotJob.where(kind: "challenge_announce").count }.by(1)

      job = BotJob.where(kind: "challenge_announce").last
      expect(job.requested_by_user_id).to eq(regular.user_id)
      expect(job.payload).to include("event" => "challenge_created", "feature_key" => "challenges")
      expect(job.payload.fetch("challenge")).to include("id" => json.dig("data", "id"), "name" => "Fall of Final Fantasy")
      expect(job.payload.dig("challenge", "pool", "game_count")).to eq(1)
    end

    it "takes a target of every game in the Pool" do
      create_challenge(as: regular, pool: { franchise_ids: [ franchise.franchise_id ], target: "all" })

      expect(json.dig("data", "pool", "target")).to eq("all")
    end

    it "refuses a target below 1, a missing target and an empty Pool" do
      create_challenge(as: regular, pool: { franchise_ids: [ franchise.franchise_id ], target: 0 })
      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("message")).to include("target")

      create_challenge(as: regular, pool: { franchise_ids: [ franchise.franchise_id ] })
      expect(response).to have_http_status(:unprocessable_content)

      create_challenge(as: regular, pool: { target: 1 })
      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("message")).to include("at least one franchise, collection or included game")
    end

    it "refuses unknown franchises and Formats that are not available yet" do
      create_challenge(as: regular, pool: { franchise_ids: [ 999_999_999 ], target: 1 })
      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("message")).to include("Unknown franchise ids: 999999999")

      create_challenge(as: regular, challenge_format: "slots")
      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("message")).to include("not available yet")
    end

    it "refuses a name over 100 characters and a missing name" do
      create_challenge(as: regular, name: "x" * 101)
      expect(response).to have_http_status(:unprocessable_content)

      create_challenge(as: regular, name: " ")
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "schedules" do
    it "is Closed after an Always Open Challenge's end date, and Open on it" do
      create_challenge(as: regular, ends_on: "2026-10-14")
      expect(json.dig("data", "open")).to be(false)

      create_challenge(as: regular, ends_on: "2026-10-15")
      expect(json.dig("data", "open")).to be(true)
    end

    it "is Open on a Season's first and last day and Closed the day before" do
      create_challenge(as: regular, schedule: "seasonal", season: { start: "10-15", end: "12-20" })
      expect(json.dig("data", "season")).to eq("start" => "10-15", "end" => "12-20", "crosses_new_year" => false)
      expect(json.dig("data", "open")).to be(true)

      create_challenge(as: regular, schedule: "seasonal", season: { start: "09-01", end: "10-15" })
      expect(json.dig("data", "open")).to be(true)

      create_challenge(as: regular, schedule: "seasonal", season: { start: "10-16", end: "12-20" })
      expect(json.dig("data", "open")).to be(false)
    end

    it "handles a Season crossing the new year" do
      create_challenge(as: regular, schedule: "seasonal", season: { start: "12-01", end: "02-28" })
      id = json.dig("data", "id")
      expect(json.dig("data", "season", "crosses_new_year")).to be(true)
      expect(json.dig("data", "open")).to be(false)

      { "2026-12-01" => true, "2027-01-15" => true, "2027-02-28" => true, "2027-03-01" => false,
        "2026-11-30" => false }.each do |day, open|
        travel_to(Time.zone.parse("#{day} 12:00:00 -05:00"))
        get "/api/v1/challenges/#{id}", headers: auth_headers_for(member)
        expect(json.dig("data", "open")).to be(open), "on #{day}"

        get "/api/v1/challenges", params: { open: open }, headers: auth_headers_for(member)
        expect(json.fetch("data").map { |c| c.fetch("id") }).to include(id), "listed as open=#{open} on #{day}"
      end
    end

    it "uses the club's time zone for today" do
      create_challenge(as: regular, ends_on: "2026-10-15")
      id = json.dig("data", "id")

      # 02:00 UTC on the 16th is still the 15th in the club's time zone.
      travel_to(Time.utc(2026, 10, 16, 2))
      get "/api/v1/challenges/#{id}", headers: auth_headers_for(member)
      expect(json.dig("data", "open")).to be(true)
    end

    it "refuses a Seasonal Challenge without a Season, an end date on one, and a day no year has" do
      create_challenge(as: regular, schedule: "seasonal")
      expect(response).to have_http_status(:unprocessable_content)

      create_challenge(as: regular, schedule: "seasonal", season: { start: "06-21", end: "09-22" }, ends_on: "2027-01-01")
      expect(response).to have_http_status(:unprocessable_content)

      create_challenge(as: regular, schedule: "seasonal", season: { start: "02-30", end: "03-10" })
      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("message")).to include("not a day of the year")
    end
  end

  describe "GET /api/v1/challenges" do
    it "filters by Open or Closed and by Challenge Format" do
      open_one = create(:challenge)
      closed_one = create(:challenge, ends_on: Date.new(2026, 1, 1))
      summer = create(:challenge, :seasonal, season: "06-21..09-22")

      get "/api/v1/challenges", params: { open: "true" }, headers: auth_headers_for(member)
      expect(json.fetch("data").map { |c| c.fetch("id") }).to contain_exactly(open_one.id)

      get "/api/v1/challenges", params: { open: "false" }, headers: auth_headers_for(member)
      expect(json.fetch("data").map { |c| c.fetch("id") }).to contain_exactly(closed_one.id, summer.id)

      get "/api/v1/challenges", params: { challenge_format: "pool" }, headers: auth_headers_for(member)
      expect(json.dig("meta", "count")).to eq(3)

      get "/api/v1/challenges", params: { challenge_format: "slots" }, headers: auth_headers_for(member)
      expect(json.fetch("data")).to eq([])
    end

    it "400s for an unknown filter value" do
      get "/api/v1/challenges", params: { open: "maybe" }, headers: auth_headers_for(member)
      expect(response).to have_http_status(:bad_request)

      get "/api/v1/challenges", params: { challenge_format: "quest" }, headers: auth_headers_for(member)
      expect(response).to have_http_status(:bad_request)
    end

    it "lists hidden Challenges only for Moderators and their Host" do
      hidden = create(:challenge, hidden: true, host: regular)
      shown = create(:challenge)

      get "/api/v1/challenges", headers: auth_headers_for(member)
      expect(json.fetch("data").map { |c| c.fetch("id") }).to eq([ shown.id ])

      get "/api/v1/challenges", headers: auth_headers_for(regular)
      expect(json.fetch("data").map { |c| c.fetch("id") }).to contain_exactly(shown.id, hidden.id)

      get "/api/v1/challenges", headers: auth_headers_for(moderator)
      expect(json.fetch("data").map { |c| c.fetch("id") }).to contain_exactly(shown.id, hidden.id)

      get "/api/v1/challenges/#{hidden.id}", headers: auth_headers_for(member)
      expect(response).to have_http_status(:not_found)

      get "/api/v1/challenges/#{hidden.id}", params: { acting_user_id: regular.user_id }, headers: service_headers
      expect(response).to have_http_status(:ok)

      get "/api/v1/challenges/#{hidden.id}", headers: service_headers
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /api/v1/challenges/:id" do
    it "shows the Pool's franchises, collections, included and excluded games" do
      collection = create(:gamedb_collection, name: "Compilation of FFVII")
      included = create(:game, title: "Chrono Trigger")
      excluded = create(:game, title: "Final Fantasy VII: Ever Crisis")
      GamedbGameFranchise.create!(game: excluded, franchise: franchise)
      create_challenge(as: regular, pool: {
        franchise_ids: [ franchise.franchise_id ], collection_ids: [ collection.collection_id ],
        included_game_ids: [ included.game_id ], excluded_game_ids: [ excluded.game_id ], target: "all"
      })

      get "/api/v1/challenges/#{json.dig('data', 'id')}", headers: auth_headers_for(member)

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "pool")).to include(
        "collections" => [ { "collection_id" => collection.collection_id, "name" => "Compilation of FFVII" } ],
        "included_games" => [ { "game_id" => included.game_id, "title" => "Chrono Trigger" } ],
        "excluded_games" => [ { "game_id" => excluded.game_id, "title" => "Final Fantasy VII: Ever Crisis" } ],
        "game_count" => 2
      )
    end
  end

  describe "editing" do
    let(:challenge) do
      create_challenge(as: regular)
      Challenge.find(json.dig("data", "id"))
    end

    def edit(as:, **data)
      patch "/api/v1/challenges/#{challenge.id}", params: { data: data }, headers: auth_headers_for(as), as: :json
    end

    it "lets the Host edit their own Challenge" do
      edit(as: regular, name: "Autumn of Final Fantasy", pool: { target: 3 })

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("name" => "Autumn of Final Fantasy", "updated_by" => regular.user_id)
      expect(json.dig("data", "pool")).to include("target" => 3,
        "franchises" => [ a_hash_including("franchise_id" => franchise.franchise_id) ])
    end

    it "refuses other members and Moderators on a member's Challenge" do
      edit(as: create(:user, role_regular: true), name: "Mine now")
      expect(response).to have_http_status(:forbidden)

      edit(as: moderator, name: "Mine now")
      expect(response).to have_http_status(:forbidden)
    end

    it "lets any Moderator edit a club-hosted Challenge" do
      create_challenge(as: moderator, hosted_by_club: true)
      id = json.dig("data", "id")

      patch "/api/v1/challenges/#{id}", params: { data: { description: "Club tradition." } },
        headers: auth_headers_for(create(:user, role_moderator: true)), as: :json

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "description")).to eq("Club tradition.")

      patch "/api/v1/challenges/#{id}", params: { data: { description: "Mine." } }, headers: auth_headers_for(regular),
        as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it "switches between Always Open and Seasonal while no Run exists" do
      edit(as: regular, schedule: "seasonal", season: { start: "09-22", end: "12-20" })

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "schedule")).to eq("seasonal")
      expect(json.dig("data", "season", "start")).to eq("09-22")
    end

    context "once a Run exists" do
      before { create(:challenge_run, challenge: challenge) }

      it "refuses changes to the rules" do
        [
          { schedule: "seasonal", season: { start: "09-22", end: "12-20" } },
          { pool: { target: 5 } },
          { pool: { excluded_game_ids: [ ff7.game_id ] } },
          { challenge_format: "slots" }
        ].each do |change|
          edit(as: regular, **change)
          expect(response.status).to be_in([ 409, 422 ]), "#{change} got #{response.status}"
        end

        edit(as: regular, pool: { target: 5 })
        expect(response).to have_http_status(:conflict)
        expect(json).to include("error" => "rules_locked", "fields" => [ "pool" ])
        expect(json.fetch("message")).to include("Name, description and end date stay editable")
        expect(challenge.reload.pool_target).to eq(2)
      end

      it "keeps name, description and end date editable, and accepts the rules sent back unchanged" do
        edit(as: regular, name: "Renamed", description: "New words", ends_on: "2027-01-31",
          schedule: "always_open", challenge_format: "pool", pool: { franchise_ids: [ franchise.franchise_id ], target: 2 })

        expect(response).to have_http_status(:ok)
        expect(json.fetch("data")).to include("name" => "Renamed", "description" => "New words", "ends_on" => "2027-01-31")
      end
    end
  end

  describe "deleting" do
    it "lets the Host delete their own Challenge while it has no Runs" do
      challenge = create(:challenge, host: regular)

      delete "/api/v1/challenges/#{challenge.id}", headers: auth_headers_for(regular)

      expect(response).to have_http_status(:ok)
      expect(Challenge.exists?(challenge.id)).to be(false)
    end

    it "refuses the Host once a Run exists, and other members" do
      challenge = create(:challenge, host: regular)
      create(:challenge_run, challenge: challenge)

      delete "/api/v1/challenges/#{challenge.id}", headers: auth_headers_for(regular)
      expect(response).to have_http_status(:conflict)
      expect(json.fetch("error")).to eq("has_runs")

      delete "/api/v1/challenges/#{challenge.id}", headers: auth_headers_for(member)
      expect(response).to have_http_status(:forbidden)
    end

    it "deletes for the member the bot names in the query" do
      challenge = create(:challenge, host: regular)

      delete "/api/v1/challenges/#{challenge.id}", params: { acting_user_id: member.user_id }, headers: service_headers
      expect(response).to have_http_status(:forbidden)

      delete "/api/v1/challenges/#{challenge.id}", params: { acting_user_id: regular.user_id }, headers: service_headers
      expect(response).to have_http_status(:ok)
    end

    it "lets a Moderator remove any Challenge, Runs included" do
      challenge = create(:challenge, host: regular)
      create(:challenge_run, challenge: challenge)

      delete "/api/v1/challenges/#{challenge.id}", headers: auth_headers_for(moderator)

      expect(response).to have_http_status(:ok)
      expect(Challenge.exists?(challenge.id)).to be(false)
    end
  end

  describe "hiding and changing the Host" do
    let(:challenge) { create(:challenge, host: regular) }

    it "lets Moderators hide and unhide a Challenge" do
      post "/api/v1/challenges/#{challenge.id}/hide", headers: auth_headers_for(moderator)
      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "hidden")).to be(true)

      post "/api/v1/challenges/#{challenge.id}/unhide", headers: auth_headers_for(moderator)
      expect(json.dig("data", "hidden")).to be(false)
    end

    it "refuses the Host and members" do
      post "/api/v1/challenges/#{challenge.id}/hide", headers: auth_headers_for(regular)

      expect(response).to have_http_status(:forbidden)
      expect(json.fetch("message")).to eq("Only Moderators and above can do that.")
    end

    it "lets Moderators hand a Challenge to another member, or to the club" do
      new_host = create(:user)

      put "/api/v1/challenges/#{challenge.id}/host", params: { data: { host_user_id: new_host.user_id } },
        headers: auth_headers_for(moderator), as: :json
      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "host", "user_id")).to eq(new_host.user_id)

      put "/api/v1/challenges/#{challenge.id}/host", params: { data: { hosted_by_club: true } },
        headers: auth_headers_for(moderator), as: :json
      expect(json.dig("data", "hosted_by_club")).to be(true)

      put "/api/v1/challenges/#{challenge.id}/host", params: { data: { host_user_id: "404" } },
        headers: auth_headers_for(moderator), as: :json
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "keeps the Host's Challenge when they lose the Regulars role" do
      regular.update!(role_regular: false)

      patch "/api/v1/challenges/#{challenge.id}", params: { data: { description: "Still mine." } },
        headers: auth_headers_for(regular), as: :json

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "host", "user_id")).to eq(regular.user_id)
    end
  end

  describe "POST /api/v1/challenges/pool_preview" do
    it "resolves franchises, collections, includes and excludes against the GameDB" do
      collection = create(:gamedb_collection)
      in_collection = create(:game, title: "Crisis Core", collection_id: collection.collection_id,
        initial_release_date: Time.utc(2007, 9, 13))
      ff7.update!(initial_release_date: Time.utc(1997, 1, 31))
      spin_off = create(:game, title: "Final Fantasy VII: Ever Crisis")
      GamedbGameFranchise.create!(game: spin_off, franchise: franchise)
      included = create(:game, title: "Chrono Trigger", initial_release_date: Time.utc(1995, 3, 11))
      create(:game, title: "Unrelated")

      post "/api/v1/challenges/pool_preview", params: { data: {
        franchise_ids: [ franchise.franchise_id ], collection_ids: [ collection.collection_id ],
        included_game_ids: [ included.game_id ], excluded_game_ids: [ spin_off.game_id ]
      } }, headers: auth_headers_for(member), as: :json

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data").map { |g| g.fetch("title") }).to eq([ "Chrono Trigger", "Final Fantasy VII", "Crisis Core" ])
      expect(json.dig("meta", "count")).to eq(3)
      expect(json.fetch("data").first).to include("game_id" => included.game_id, "cover_url" => nil)
      expect(in_collection.game_id).to be_present
    end

    it "refuses an empty definition and a game both included and excluded" do
      post "/api/v1/challenges/pool_preview", params: { data: { franchise_ids: [] } }, headers: auth_headers_for(member),
        as: :json
      expect(response).to have_http_status(:unprocessable_content)

      post "/api/v1/challenges/pool_preview", params: { data: {
        included_game_ids: [ ff7.game_id ], excluded_game_ids: [ ff7.game_id ]
      } }, headers: auth_headers_for(member), as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("message")).to include("both included and excluded")
    end
  end

  describe "GET /api/v1/challenges/pool_sources" do
    it "finds franchises and collections by name, with their game counts" do
      collection = create(:gamedb_collection, name: "Final Fantasy Tactics")
      create(:game, collection_id: collection.collection_id)
      create(:game, collection_id: collection.collection_id)

      get "/api/v1/challenges/pool_sources", params: { q: "final fan" }, headers: auth_headers_for(member)

      expect(json.fetch("data")).to eq([
        { "kind" => "franchise", "id" => franchise.franchise_id, "name" => "Final Fantasy", "game_count" => 1 },
        { "kind" => "collection", "id" => collection.collection_id, "name" => "Final Fantasy Tactics", "game_count" => 2 }
      ])
    end

    it "400s without a query" do
      get "/api/v1/challenges/pool_sources", headers: auth_headers_for(member)

      expect(response).to have_http_status(:bad_request)
    end
  end

  describe "the challenges Feature Flag", feature_flags: :none do
    it "starts in Preview: staff can use Challenges, other members get 404" do
      admin = create(:user, role_admin: true, role_regular: true)

      get "/api/v1/challenges", headers: auth_headers_for(regular)
      expect(response).to have_http_status(:not_found)

      get "/api/v1/challenges", headers: auth_headers_for(admin)
      expect(response).to have_http_status(:ok)
    end

    it "refuses the bot's writes for a member who cannot use it, and everyone when Off" do
      post "/api/v1/challenges", params: { data: pool_challenge(acting_user_id: regular.user_id) },
        headers: service_headers, as: :json
      expect(response).to have_http_status(:forbidden)
      expect(json.fetch("error")).to eq("feature_unavailable")

      set_feature_flag("challenges", "off")
      get "/api/v1/challenges", headers: auth_headers_for(create(:user, role_admin: true))
      expect(response).to have_http_status(:not_found)
    end
  end
end
