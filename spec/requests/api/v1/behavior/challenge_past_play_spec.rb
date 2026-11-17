# frozen_string_literal: true

require "rails_helper"

# Counts past play (spec #376, ticket #382): the Host of an Always Open
# Slots Challenge lets earlier play count, as Years Alive needs. A member then
# picks Game Completions dated before their Run started for open slots they
# fit. Earlier play never fills a slot by itself.
RSpec.describe "api/v1/challenges Counts past play behavior", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:regular) { create(:user, role_member: true, role_regular: true) }
  let(:member) { create(:user, role_member: true) }

  # Mid-October 2026 in the club's time zone.
  around { |example| travel_to(Time.zone.parse("2026-10-15 12:00:00 -04:00")) { example.run } }

  describe "the setting" do
    def slots_challenge(schedule: "always_open", **slots)
      data = { name: "Years Alive", description: "One game from every year you've been alive.",
               challenge_format: "slots", schedule: schedule, slots: { first_year: "birth_year",
                                                                        last_year: "current_year", **slots } }
      data[:season] = { start: "06-21", end: "09-22" } if schedule == "seasonal"
      data
    end

    def create_challenge(**data)
      post "/api/v1/challenges", params: { data: slots_challenge(**data) }, headers: auth_headers_for(regular),
        as: :json
    end

    it "is accepted on an Always Open Slots Challenge, and off unless the Host turns it on" do
      create_challenge(counts_past_play: true)

      expect(response).to have_http_status(:created)
      expect(json.dig("data", "slots")).to include("counts_past_play" => true)

      create_challenge

      expect(response).to have_http_status(:created)
      expect(json.dig("data", "slots")).to include("counts_past_play" => false)
    end

    it "is refused on a Seasonal Challenge, including by switching an Always Open one to Seasonal" do
      create_challenge(schedule: "seasonal", counts_past_play: true)

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("message")).to include("Counts past play is only for Always Open Challenges")

      create_challenge(schedule: "seasonal", counts_past_play: false)
      expect(response).to have_http_status(:created)

      create_challenge(counts_past_play: true)
      id = json.dig("data", "id")
      patch "/api/v1/challenges/#{id}", params: { data: { schedule: "seasonal", season: { start: "06-21", end: "09-22" } } },
        headers: auth_headers_for(regular), as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("message")).to include("Counts past play is only for Always Open Challenges")
    end

    it "is dropped when a Run-less Challenge switches to another Format" do
      create_challenge(counts_past_play: true)
      id = json.dig("data", "id")
      pool = { included_game_ids: [ create(:game).game_id ], target: 1 }

      patch "/api/v1/challenges/#{id}", params: { data: { challenge_format: "pool", pool: pool, schedule: "seasonal",
                                                          season: { start: "06-21", end: "09-22" } } },
        headers: auth_headers_for(regular), as: :json

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "challenge_format")).to eq("pool")
    end

    it "refuses a value that isn't true or false" do
      create_challenge(counts_past_play: "sometimes")

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("message")).to include("counts_past_play must be true or false")
    end

    it "is locked once a Run exists, and editable before" do
      create_challenge(counts_past_play: true)
      id = json.dig("data", "id")

      patch "/api/v1/challenges/#{id}", params: { data: { slots: { counts_past_play: false } } },
        headers: auth_headers_for(regular), as: :json
      expect(json.dig("data", "slots")).to include("counts_past_play" => false, "first_year" => "birth_year")

      create(:challenge_run, challenge: Challenge.find(id))
      patch "/api/v1/challenges/#{id}", params: { data: { slots: { counts_past_play: true } } },
        headers: auth_headers_for(regular), as: :json

      expect(response).to have_http_status(:conflict)
      expect(json).to include("error" => "rules_locked", "fields" => [ "slots" ])
    end
  end

  # A Slots Challenge from 1995 to 1999 that counts past play unless told
  # otherwise.
  def slots(first = 1995, last = 1999, counts_past_play: true, **attrs)
    create(:challenge, challenge_format: "slots", pool_target: nil, slots_first_year: first, slots_last_year: last,
      counts_past_play: counts_past_play, **attrs)
  end

  def start_run(challenge)
    post "/api/v1/challenges/#{challenge.id}/runs", headers: auth_headers_for(member), as: :json
    expect(response).to have_http_status(:created)
    json.dig("data", "id")
  end

  def run_json(run_id)
    get "/api/v1/challenge_runs/#{run_id}", headers: auth_headers_for(member)
    json.fetch("data")
  end

  # A game first released in `first` (a year), and in each of `also` in some
  # region or on some platform.
  def game(title, first, *also)
    create(:game, title: title, initial_release_date: Time.utc(first, 6, 1)).tap do |created|
      also.each { |year| create(:release, game: created, release_date: Time.utc(year, 3, 1)) }
    end
  end

  def log_completion(game, on: "2026-10-15", as: member)
    post "/api/v1/users/#{as.user_id}/completions",
      params: { data: { gamedb_game_id: game.game_id, completion_type: "Main Story", completed_at: on } },
      headers: auth_headers_for(as), as: :json
    expect(response).to have_http_status(:created)
    json.dig("data", "completion_id")
  end

  # A Game Completion without a date, as imports leave them.
  def undated_completion(game)
    create(:completion, user: member, game: game).tap { |completion| completion.update_columns(completed_at: nil) }
  end

  def pick(run_id, completion_id, year, as: auth_headers_for(member))
    post "/api/v1/challenge_runs/#{run_id}/past_pick", params: { data: { completion_id: completion_id, slot_year: year } },
      headers: as, as: :json
  end

  # The Run's filled slots, as year => title.
  def filled(run_id)
    run_json(run_id).dig("slots", "years").select { |slot| slot["game_id"] }.to_h { |slot| slot.values_at("year", "title") }
  end

  describe "picking a past Game Completion" do
    let(:suikoden) { game("Suikoden", 1995) }
    let(:chrono) { game("Chrono Trigger", 1995, 1999) }
    let(:xenogears) { game("Xenogears", 1998) }

    it "never fills a slot with earlier play by itself, while new play keeps filling slots" do
      log_completion(suikoden, on: "2019-03-02")
      run_id = start_run(slots)
      log_completion(xenogears, on: "2020-01-01")

      expect(run_json(run_id).fetch("entries")).to eq([])

      log_completion(chrono)

      expect(filled(run_id)).to eq(1995 => "Chrono Trigger")
    end

    it "fills an open slot the Game Completion fits, marked as picked by hand" do
      completion_id = log_completion(chrono, on: "2019-03-02")
      run_id = start_run(slots)

      pick(run_id, completion_id, 1999)

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "entries")).to contain_exactly(a_hash_including("title" => "Chrono Trigger",
        "state" => "cleared", "slot_year" => 1999, "picked_by_hand" => true, "cleared_on" => "2019-03-02"))
      expect(json.dig("data", "progress")).to include("cleared" => 1, "target" => 5)
    end

    it "takes an undated Game Completion" do
      completion = undated_completion(suikoden)
      run_id = start_run(slots)

      pick(run_id, completion.completion_id, 1995)

      expect(response).to have_http_status(:ok)
      expect(filled(run_id)).to eq(1995 => "Suikoden")
    end

    it "keeps the pick through refreshes, and drops it when the Game Completion is deleted" do
      completion_id = log_completion(suikoden, on: "2019-03-02")
      run_id = start_run(slots)
      pick(run_id, completion_id, 1995)

      log_completion(chrono)
      log_completion(xenogears)
      log_completion(game("Suikoden II", 1995))

      expect(filled(run_id)).to eq(1995 => "Suikoden", 1998 => "Xenogears", 1999 => "Chrono Trigger")

      delete "/api/v1/completions/#{completion_id}", headers: auth_headers_for(member)

      expect(filled(run_id)).to eq(1995 => "Suikoden II", 1998 => "Xenogears", 1999 => "Chrono Trigger")
      expect(run_json(run_id).fetch("entries").map { |entry| entry["title"] }).not_to include("Suikoden")
    end

    it "Clears a game the member is replaying, which stays Cleared while it is in Now Playing" do
      completion_id = log_completion(suikoden, on: "2019-03-02")
      run_id = start_run(slots)
      post "/api/v1/users/#{member.user_id}/now_playing", params: { data: { gamedb_game_id: suikoden.game_id } },
        headers: auth_headers_for(member), as: :json
      expect(run_json(run_id).fetch("entries")).to contain_exactly(a_hash_including("state" => "in_progress"))

      pick(run_id, completion_id, 1995)
      log_completion(xenogears)

      expect(run_json(run_id).fetch("entries")).to contain_exactly(
        a_hash_including("title" => "Suikoden", "state" => "cleared", "slot_year" => 1995),
        a_hash_including("title" => "Xenogears", "state" => "cleared", "slot_year" => 1998)
      )
    end

    it "Finishes a Run whose last open slot it fills, and keeps it once Finished" do
      completion_id = log_completion(suikoden, on: "2019-03-02")
      run_id = start_run(slots(1995, 1996))
      log_completion(game("Tobal No. 1", 1996))

      expect { pick(run_id, completion_id, 1995) }
        .to change { BotJob.where(kind: "challenge_announce").count }.by(1)
      expect(json.dig("data", "status")).to eq("finished")

      delete "/api/v1/completions/#{completion_id}", headers: auth_headers_for(member)

      expect(filled(run_id)).to eq(1995 => "Suikoden", 1996 => "Tobal No. 1")
    end

    it "can be moved to another year like any Cleared game" do
      completion_id = log_completion(chrono, on: "2019-03-02")
      run_id = start_run(slots)
      pick(run_id, completion_id, 1995)

      post "/api/v1/challenge_runs/#{run_id}/slot_move", params: { data: { game_id: chrono.game_id, slot_year: 1999 } },
        headers: auth_headers_for(member), as: :json

      expect(response).to have_http_status(:ok)
      expect(filled(run_id)).to eq(1999 => "Chrono Trigger")
    end

    it "is refused when the Challenge doesn't count past play" do
      completion_id = log_completion(suikoden, on: "2019-03-02")
      run_id = start_run(slots(counts_past_play: false))

      pick(run_id, completion_id, 1995)

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("error")).to eq("past_play_off")
      expect(filled(run_id)).to eq({})
    end

    it "refuses a Game Completion that isn't the member's earlier play" do
      run_id = start_run(slots)
      today = log_completion(chrono)
      other = log_completion(suikoden, on: "2019-03-02", as: create(:user, role_member: true))

      [ today, other, 999_999_999 ].each do |completion_id|
        pick(run_id, completion_id, 1995)
        expect(response).to have_http_status(:unprocessable_content)
        expect(json.fetch("error")).to eq("not_past_completion")
      end
    end

    it "refuses a year the game doesn't fit, a filled year, a year outside the Run and a game already Cleared on it" do
      earlier_xenogears = log_completion(xenogears, on: "2019-03-02")
      earlier_suikoden = log_completion(suikoden, on: "2019-03-02")
      earlier_chrono = log_completion(chrono, on: "2018-01-01")
      run_id = start_run(slots)
      suikoden_ii = game("Suikoden II", 1995, 1999)
      log_completion(suikoden_ii)
      log_completion(chrono)

      pick(run_id, earlier_xenogears, 1995)
      expect(response).to have_http_status(:unprocessable_content)
      expect(json).to include("error" => "slot_not_fitting")
      expect(json.fetch("message")).to include("Xenogears", "1995")

      pick(run_id, earlier_suikoden, 1995)
      expect(response).to have_http_status(:conflict)
      expect(json).to include("error" => "slot_filled", "game_id" => suikoden_ii.game_id)

      pick(run_id, earlier_xenogears, 2005)
      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("error")).to eq("slot_out_of_range")

      pick(run_id, earlier_chrono, 1999)
      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("error")).to eq("already_cleared")

      expect(filled(run_id)).to eq(1995 => "Suikoden II", 1999 => "Chrono Trigger")
    end

    it "refuses another member, a Run that isn't Active and a Pool Run" do
      completion_id = log_completion(suikoden, on: "2019-03-02")
      run_id = start_run(slots)

      pick(run_id, completion_id, 1995, as: auth_headers_for(create(:user)))
      expect(response).to have_http_status(:forbidden)

      post "/api/v1/challenge_runs/#{run_id}/abandon", headers: auth_headers_for(member), as: :json
      pick(run_id, completion_id, 1995)
      expect(response).to have_http_status(:conflict)
      expect(json.fetch("error")).to eq("run_not_active")

      pool_run = create(:challenge_run, user: member)
      pick(pool_run.id, completion_id, 1995)
      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("error")).to eq("not_slots")
    end

    it "refuses a field that isn't a whole number" do
      run_id = start_run(slots)

      pick(run_id, "abc", 1995)

      expect(response).to have_http_status(:bad_request)
    end

    it "lets the bot pick for the member it names" do
      completion_id = log_completion(suikoden, on: "2019-03-02")
      run_id = start_run(slots)

      post "/api/v1/challenge_runs/#{run_id}/past_pick",
        params: { data: { acting_user_id: member.user_id, completion_id: completion_id, slot_year: 1995 } },
        headers: service_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(filled(run_id)).to eq(1995 => "Suikoden")
    end
  end

  describe "listing the past Game Completions a member can pick" do
    it "lists earlier Game Completions with the open years each fits, leaving out what can't be picked" do
      chrono = game("Chrono Trigger", 1995, 1999)
      earlier_chrono = log_completion(chrono, on: "2018-01-01")
      log_completion(game("Persona 5", 2016), on: "2018-01-01")
      earlier_xenogears = log_completion(game("Xenogears", 1998), on: "2019-03-02")
      # Fits only 1995, which Suikoden II fills.
      undated_completion(game("Suikoden", 1995))
      run_id = start_run(slots)
      log_completion(game("Suikoden II", 1995))

      get "/api/v1/challenge_runs/#{run_id}/past_play", headers: auth_headers_for(member)

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to contain_exactly(
        a_hash_including("completion_id" => earlier_chrono, "game_id" => chrono.game_id, "title" => "Chrono Trigger",
          "completed_at" => "2018-01-01", "open_years" => [ 1999 ]),
        a_hash_including("completion_id" => earlier_xenogears, "title" => "Xenogears", "open_years" => [ 1998 ])
      )

      get "/api/v1/challenge_runs/#{run_id}/past_play", params: { q: "xeno" }, headers: auth_headers_for(member)
      expect(json.fetch("data").map { |row| row["title"] }).to eq([ "Xenogears" ])

      log_completion(chrono)
      get "/api/v1/challenge_runs/#{run_id}/past_play", headers: auth_headers_for(member)
      expect(json.fetch("data").map { |row| row["title"] }).to eq([ "Xenogears" ])
    end

    it "gives each Game Completion its game's cover, in a fixed number of queries" do
      chrono = game("Chrono Trigger", 1995).tap { |covered| create(:game_image, :primary, game: covered) }
      log_completion(chrono, on: "2018-01-01")
      run_id = start_run(slots)
      count_queries = lambda do
        queries = 0
        subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
          queries += 1 unless payload[:name] == "SCHEMA"
        end
        begin
          get "/api/v1/challenge_runs/#{run_id}/past_play", headers: auth_headers_for(member)
        ensure
          ActiveSupport::Notifications.unsubscribe(subscriber)
        end
        queries
      end

      small = count_queries.call
      expect(json.fetch("data")).to contain_exactly(
        a_hash_including("title" => "Chrono Trigger", "cover_url" => chrono.cover_url)
      )

      xenogears = game("Xenogears", 1998).tap { |covered| create(:game_image, :primary, game: covered) }
      log_completion(xenogears, on: "2019-03-02")
      log_completion(game("Suikoden", 1996), on: "2019-04-02")
      large = count_queries.call

      expect(json.fetch("data").map { |row| row.values_at("title", "cover_url") }).to contain_exactly(
        [ "Chrono Trigger", chrono.cover_url ], [ "Xenogears", xenogears.cover_url ], [ "Suikoden", nil ]
      )
      expect(large).to eq(small)
    end

    it "lists undated Game Completions" do
      undated = undated_completion(game("Suikoden", 1995))
      run_id = start_run(slots)

      get "/api/v1/challenge_runs/#{run_id}/past_play", headers: auth_headers_for(member)

      expect(json.fetch("data")).to contain_exactly(a_hash_including("completion_id" => undated.completion_id,
        "completed_at" => nil, "open_years" => [ 1995 ]))
    end

    it "is refused when the Challenge doesn't count past play, and for another member" do
      run_id = start_run(slots(counts_past_play: false))

      get "/api/v1/challenge_runs/#{run_id}/past_play", headers: auth_headers_for(member)
      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("error")).to eq("past_play_off")

      get "/api/v1/challenge_runs/#{run_id}/past_play", headers: auth_headers_for(create(:user))
      expect(response).to have_http_status(:forbidden)
    end
  end
end
