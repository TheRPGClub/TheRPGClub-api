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

    it "carries up to 10 Pool games for the post's cover wall, those with a cover first" do
      covered = %w[Xenogears Chrono Okami].map do |title|
        create(:game, title: title).tap { |game| create(:game_image, :primary, game: game) }
      end
      (1..9).each { |n| create(:game, title: "Final Fantasy #{n}") }
      GamedbGame.where.not(game_id: ff7.game_id).find_each { |game| GamedbGameFranchise.find_or_create_by!(game: game, franchise: franchise) }

      create_challenge(as: regular)

      pool_games = BotJob.where(kind: "challenge_announce").last.payload.fetch("pool_games")
      expect(pool_games.size).to eq(10)
      expect(pool_games.first(3).map { |game| game["title"] }).to eq(%w[Chrono Okami Xenogears])
      expect(pool_games.first).to eq("game_id" => covered[1].game_id, "title" => "Chrono",
        "cover_url" => covered[1].cover_url)
      expect(pool_games.last).to include("cover_url" => nil)
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

    it "refuses unknown franchises and unknown Formats" do
      create_challenge(as: regular, pool: { franchise_ids: [ 999_999_999 ], target: 1 })
      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("message")).to include("Unknown franchise ids: 999999999")

      create_challenge(as: regular, challenge_format: "bingo")
      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("message")).to include("challenge_format must be one of pool, slots, assignment")
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

    it "finds Challenges whose name contains q, ignoring case" do
      fall = create(:challenge, name: "Fall of Final Fantasy")
      winter = create(:challenge, name: "A FINAL Winter")
      create(:challenge, name: "Summer of Zelda")
      create(:challenge, name: "100% Complete")

      get "/api/v1/challenges", params: { q: " final " }, headers: auth_headers_for(member)
      expect(json.fetch("data").map { |c| c.fetch("id") }).to contain_exactly(fall.id, winter.id)

      get "/api/v1/challenges", params: { q: "%" }, headers: auth_headers_for(member)
      expect(json.fetch("data").map { |c| c.fetch("name") }).to eq([ "100% Complete" ])

      get "/api/v1/challenges", params: { q: "" }, headers: auth_headers_for(member)
      expect(json.dig("meta", "count")).to eq(4)
    end

    it "gives each listed Challenge its Run and Finished counts and its first Pool covers" do
      busy = create(:challenge)
      quiet = create(:challenge)
      %w[active finished finished abandoned].each { |status| create(:challenge_run, challenge: busy, status: status) }
      covered = %w[Xenogears Chrono Okami Ys Zelda].map do |title|
        create(:game, title: title).tap { |game| create(:game_image, :primary, game: game) }
      end
      uncovered = create(:game, title: "Arc")
      (covered + [ uncovered ]).each { |game| ChallengePoolGame.create!(challenge: busy, game: game, inclusion: "include") }

      get "/api/v1/challenges", headers: auth_headers_for(member)

      listed = json.fetch("data").index_by { |c| c.fetch("id") }
      expect(listed.fetch(busy.id)).to include("run_count" => 4, "finished_count" => 2)
      expect(listed.fetch(busy.id).fetch("pool_games")).to eq(
        [ covered[1], covered[2], covered[0], covered[3] ].map do |game|
          { "game_id" => game.game_id, "title" => game.title, "cover_url" => game.cover_url }
        end
      )
      expect(listed.fetch(quiet.id)).to include("run_count" => 0, "finished_count" => 0)
      expect(listed.fetch(quiet.id).fetch("pool_games").size).to eq(1)
    end

    it "leaves Pool covers off Slots Challenges and reads a page in a fixed number of queries" do
      slots = create(:challenge, challenge_format: "slots", slots_first_year: 1990, slots_last_year: 1999)
      count_queries = lambda do
        Features.forget_cached_states!
        queries = 0
        subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
          queries += 1 unless payload[:name] == "SCHEMA"
        end
        begin
          get "/api/v1/challenges", headers: auth_headers_for(member)
        ensure
          ActiveSupport::Notifications.unsubscribe(subscriber)
        end
        queries
      end

      small = count_queries.call
      expect(json.fetch("data").find { |c| c["id"] == slots.id }).to include("pool_games" => [], "run_count" => 0)

      3.times { create(:challenge).tap { |c| create(:challenge_run, challenge: c, status: "finished") } }
      large = count_queries.call

      expect(json.fetch("data").size).to eq(4)
      expect(large).to eq(small)
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

  describe "the Challenge tint" do
    # The curated fallbacks from the Challenges inks (DESIGN.md), as fill / hi.
    curated = {
      "teal" => %w[#1f6b67 #6fd6cc], "cobalt" => %w[#2c4f8e #9ab8f2], "umber" => %w[#7a531c #e0b56e],
      "moss" => %w[#3b5a2b #a9cf86], "azure" => %w[#2a5ea6 #9cc2f5], "slate" => %w[#3a3a52 #b4b4d6],
      "ochre" => %w[#8a6417 #e6c36a]
    }
    holly = { "fill" => "#1c6545", "hi" => "#3fbf8a" }
    let(:curated_tints) { curated.values.map { |fill, hi| { "fill" => fill, "hi" => hi } } }

    it "gives each new Challenge a curated tint, turning through the list so neighbours differ" do
      ids = Array.new(7) do |n|
        create_challenge(as: regular, name: "Challenge #{n}")
        json.dig("data", "id")
      end

      tints = ids.map do |id|
        get "/api/v1/challenges/#{id}", headers: auth_headers_for(member)
        json.dig("data", "tint")
      end
      expect(tints).to match_array(curated_tints)
    end

    it "keeps a Challenge's tint when its name changes" do
      create_challenge(as: regular)
      id = json.dig("data", "id")
      tint = json.dig("data", "tint")

      patch "/api/v1/challenges/#{id}", params: { data: { name: "Renamed" } }, headers: auth_headers_for(regular),
        as: :json

      expect(json.dig("data", "tint")).to eq(tint)
    end

    it "gives Secret Santa (an Assignment Challenge) holly, which no other Challenge gets by default" do
      post "/api/v1/challenges", params: { data: { name: "Secret Santa", challenge_format: "assignment",
                                                   schedule: "always_open", hosted_by_club: true } },
        headers: auth_headers_for(moderator), as: :json

      expect(response).to have_http_status(:created)
      expect(json.dig("data", "tint")).to eq(holly)
    end

    describe "set by the Host or staff" do
      let(:challenge_id) do
        create_challenge(as: regular)
        json.dig("data", "id")
      end

      def edit(as:, **data)
        patch "/api/v1/challenges/#{challenge_id}", params: { data: data }, headers: auth_headers_for(as), as: :json
      end

      it "lets the Host pick a curated tint by name, or any readable pair, and go back to the curated one" do
        curated_tint = (get "/api/v1/challenges/#{challenge_id}", headers: auth_headers_for(member)) &&
          json.dig("data", "tint")

        edit(as: regular, tint: "ochre")
        expect(json.dig("data", "tint")).to eq("fill" => "#8a6417", "hi" => "#e6c36a")

        edit(as: regular, tint: { fill: "#5A2D82", hi: " #D9B8FF " })
        expect(json.dig("data", "tint")).to eq("fill" => "#5a2d82", "hi" => "#d9b8ff")

        edit(as: regular, tint: nil)
        expect(json.dig("data", "tint")).to eq(curated_tint)
      end

      it "takes a tint on create" do
        create_challenge(as: regular, tint: "holly")

        expect(json.dig("data", "tint")).to eq(holly)
      end

      it "keeps the tint editable once the Challenge has Runs" do
        create(:challenge_run, challenge: Challenge.find(challenge_id))

        edit(as: regular, tint: "slate")

        expect(response).to have_http_status(:ok)
        expect(json.dig("data", "tint")).to eq("fill" => "#3a3a52", "hi" => "#b4b4d6")
      end

      it "refuses a tint whose type would not be readable, an unknown name and a colour that is not #rrggbb" do
        original = (get "/api/v1/challenges/#{challenge_id}", headers: auth_headers_for(member)) &&
          json.dig("data", "tint")

        edit(as: regular, tint: { fill: "#ffd400", hi: "#ffe680" })
        expect(response).to have_http_status(:unprocessable_content)
        expect(json.fetch("message")).to include("fill is too light for paper type")

        edit(as: regular, tint: { fill: "#1f6b67", hi: "#1f6b67" })
        expect(json.fetch("message")).to include("hi is too dark to read on ink")

        edit(as: regular, tint: "crimson")
        expect(json.fetch("message")).to include("crimson is not a curated tint")

        edit(as: regular, tint: { fill: "teal", hi: "#6fd6cc" })
        expect(json.fetch("message")).to include("#rrggbb")

        get "/api/v1/challenges/#{challenge_id}", headers: auth_headers_for(member)
        expect(json.dig("data", "tint")).to eq(original)
      end

      it "lets a Moderator change any Challenge's tint, and the Host their own, but no other member" do
        put "/api/v1/challenges/#{challenge_id}/tint", params: { data: { tint: "azure" } },
          headers: auth_headers_for(moderator), as: :json
        expect(response).to have_http_status(:ok)
        expect(json.dig("data", "tint")).to eq("fill" => "#2a5ea6", "hi" => "#9cc2f5")
        expect(json.dig("data", "updated_by")).to eq(moderator.user_id)

        put "/api/v1/challenges/#{challenge_id}/tint", params: { data: { tint: "moss" } },
          headers: auth_headers_for(regular), as: :json
        expect(json.dig("data", "tint")).to eq("fill" => "#3b5a2b", "hi" => "#a9cf86")

        put "/api/v1/challenges/#{challenge_id}/tint", params: { data: { tint: "teal" } },
          headers: auth_headers_for(create(:user, role_regular: true)), as: :json
        expect(response).to have_http_status(:forbidden)
        expect(json.fetch("message")).to eq("Only the Host or a Moderator can change this Challenge's tint.")

        put "/api/v1/challenges/#{challenge_id}/tint", params: { data: { tint: "teal", acting_user_id: moderator.user_id } },
          headers: service_headers, as: :json
        expect(json.dig("data", "tint")).to eq("fill" => "#1f6b67", "hi" => "#6fd6cc")
      end

      it "requires tint in the body of PUT tint" do
        put "/api/v1/challenges/#{challenge_id}/tint", params: { data: { colour: "teal" } },
          headers: auth_headers_for(moderator), as: :json
        expect(response).to have_http_status(:unprocessable_content)
        expect(json.fetch("message")).to eq("tint is required: a curated tint's name, { fill, hi } or null")
      end
    end
  end

  describe "the key art" do
    # Image URLs need a public base URL, which CI doesn't set.
    around do |example|
      original = ENV["BACKBLAZE_PUBLIC_BASE_URL"]
      ENV["BACKBLAZE_PUBLIC_BASE_URL"] = "https://cdn.example.test/club"
      example.run
    ensure
      original.nil? ? ENV.delete("BACKBLAZE_PUBLIC_BASE_URL") : ENV["BACKBLAZE_PUBLIC_BASE_URL"] = original
    end

    def in_pool(title)
      create(:game, title: title).tap { |game| GamedbGameFranchise.create!(game: game, franchise: franchise) }
    end

    def key_art_url(id)
      get "/api/v1/challenges/#{id}", headers: auth_headers_for(member)
      json.dig("data", "key_art_url")
    end

    it "is the artwork of the first Pool game by title that has artwork, its primary one first" do
      create(:game_image, game: in_pool("Bravely Default"), kind: "cover")
      create(:game_image, game: in_pool("Xenogears"), kind: "artwork")
      okami = in_pool("Okami")
      create(:game_image, game: okami, kind: "artwork", position: 1)
      primary = create(:game_image, game: okami, kind: "artwork", position: 2, is_primary: true)
      create_challenge(as: regular)

      expect(key_art_url(json.dig("data", "id"))).to eq(primary.url)
    end

    it "falls back to the first Pool game's cover, and is null without either" do
      create_challenge(as: regular)
      id = json.dig("data", "id")
      expect(key_art_url(id)).to be_nil

      cover = create(:game_image, game: in_pool("Xenogears"), kind: "cover")
      create(:game_image, game: in_pool("Zelda"), kind: "cover")

      expect(key_art_url(id)).to eq(cover.url)
    end

    it "leaves out games excluded from the Pool" do
      create(:game_image, game: ff7, kind: "artwork")
      cover = create(:game_image, game: in_pool("Xenogears"), kind: "cover")
      create_challenge(as: regular, pool: { franchise_ids: [ franchise.franchise_id ],
                                            excluded_game_ids: [ ff7.game_id ], target: 1 })

      expect(key_art_url(json.dig("data", "id"))).to eq(cover.url)
    end

    it "is null for Slots and Assignment Challenges, whose pages draw their Format's picture, and in lists" do
      create(:game_image, game: ff7, kind: "artwork")
      post "/api/v1/challenges", params: { data: { name: "Birth Years", challenge_format: "slots",
                                                   schedule: "always_open",
                                                   slots: { first_year: 1990, last_year: 1999 } } },
        headers: auth_headers_for(regular), as: :json
      expect(key_art_url(json.dig("data", "id"))).to be_nil

      create_challenge(as: regular)
      expect(json.dig("data", "key_art_url")).to be_present

      get "/api/v1/challenges", headers: auth_headers_for(member)
      expect(json.fetch("data").map { |challenge| challenge.fetch("key_art_url") }).to eq([ nil, nil ])
    end

    it "comes with the tint in the new Challenge's post" do
      artwork = create(:game_image, game: ff7, kind: "artwork")
      create_challenge(as: regular)

      challenge = BotJob.where(kind: "challenge_announce").last.payload.fetch("challenge")
      expect(challenge).to include("key_art_url" => artwork.url, "tint" => json.dig("data", "tint"))
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
