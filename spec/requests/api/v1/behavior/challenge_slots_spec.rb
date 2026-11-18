# frozen_string_literal: true

require "rails_helper"

# Slots Challenges (spec #376, ticket #381): one slot per release year in a
# range, such as Years Alive from the member's birth year to the current
# year. Slots fill themselves from the member's Game Completions.
RSpec.describe "api/v1/challenges Slots behavior", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:regular) { create(:user, role_member: true, role_regular: true) }
  let(:member) { create(:user, role_member: true) }

  # Mid-October 2026 in the club's time zone.
  around { |example| travel_to(Time.zone.parse("2026-10-15 12:00:00 -04:00")) { example.run } }

  def slots_challenge(**slots)
    { name: "Years Alive", description: "One game from every year you've been alive.",
      challenge_format: "slots", schedule: "always_open", slots: slots }
  end

  def create_challenge(as: regular, **slots)
    post "/api/v1/challenges", params: { data: slots_challenge(**slots) }, headers: auth_headers_for(as), as: :json
  end

  describe "creating a Slots Challenge" do
    it "takes a fixed or birth-year first year and a fixed or current last year" do
      create_challenge(first_year: "birth_year", last_year: "current_year")

      expect(response).to have_http_status(:created)
      expect(json.fetch("data")).to include("challenge_format" => "slots", "pool" => nil,
        "slots" => { "first_year" => "birth_year", "last_year" => "current_year", "counts_past_play" => false })

      create_challenge(first_year: 1990, last_year: 1999)

      expect(response).to have_http_status(:created)
      expect(json.dig("data", "slots")).to eq("first_year" => 1990, "last_year" => 1999, "counts_past_play" => false)

      create_challenge(first_year: 2000, last_year: "current_year")
      expect(json.dig("data", "slots")).to eq("first_year" => 2000, "last_year" => "current_year", "counts_past_play" => false)

      create_challenge(first_year: "birth_year", last_year: 2009)
      expect(json.dig("data", "slots")).to eq("first_year" => "birth_year", "last_year" => 2009, "counts_past_play" => false)
    end

    it "refuses a range that ends before it starts, a year that isn't one, and missing settings" do
      create_challenge(first_year: 2000, last_year: 1999)
      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("message")).to include("first_year must not come after last_year")

      create_challenge(first_year: 2027, last_year: "current_year")
      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("message")).to include("must not come after the current year")

      create_challenge(first_year: "1990s", last_year: "current_year")
      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("message")).to include('first_year must be a year from 1900 to 2100, or "birth_year"')

      create_challenge(first_year: 1990)
      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("message")).to include("last_year is required")

      post "/api/v1/challenges", params: { data: slots_challenge.except(:slots) }, headers: auth_headers_for(regular),
        as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("message")).to include("slots is required")
    end

    it "locks the range once a Run exists, and keeps it editable before" do
      create_challenge(first_year: 1990, last_year: 1999)
      id = json.dig("data", "id")

      patch "/api/v1/challenges/#{id}", params: { data: { slots: { last_year: 2009 } } },
        headers: auth_headers_for(regular), as: :json
      expect(json.dig("data", "slots")).to eq("first_year" => 1990, "last_year" => 2009, "counts_past_play" => false)

      create(:challenge_run, challenge: Challenge.find(id))
      patch "/api/v1/challenges/#{id}", params: { data: { slots: { first_year: "birth_year" } } },
        headers: auth_headers_for(regular), as: :json

      expect(response).to have_http_status(:conflict)
      expect(json).to include("error" => "rules_locked", "fields" => [ "slots" ])
    end
  end

  # A Slots Challenge ranging over `first`..`last` (nil: the member's birth
  # year, and the current year).
  def slots(first = nil, last = nil, **attrs)
    create(:challenge, challenge_format: "slots", pool_target: nil, slots_first_year: first, slots_last_year: last,
      **attrs)
  end

  def set_birth_date(value)
    put "/api/v1/users/#{member.user_id}/birth_date", params: { data: { birth_date: value } },
      headers: auth_headers_for(member), as: :json
    expect(response).to have_http_status(:ok)
  end

  def start(challenge)
    post "/api/v1/challenges/#{challenge.id}/runs", headers: auth_headers_for(member), as: :json
  end

  def start_run(challenge)
    start(challenge)
    expect(response).to have_http_status(:created)
    json.dig("data", "id")
  end

  def run_json(run_id)
    get "/api/v1/challenge_runs/#{run_id}", headers: auth_headers_for(member)
    json.fetch("data")
  end

  describe "starting a Run" do
    it "refuses a birth-year Run without a Birth Date, saying the birth year will show" do
      start(slots)

      expect(response).to have_http_status(:conflict)
      expect(json.fetch("error")).to eq("birth_date_required")
      expect(json.fetch("message")).to include("Birth Date").and include("birth year")
    end

    it "copies the birth year as the first year, tells the member it will show, and keeps it" do
      set_birth_date("1990-05-04")

      start(slots)

      expect(response).to have_http_status(:created)
      expect(json.dig("data", "slots")).to include("first_year" => 1990, "last_year" => 2026, "growing" => true)
      expect(json.dig("meta", "notices")).to contain_exactly(
        a_hash_including("code" => "birth_year_shown", "message" => a_string_including("1990"))
      )
      run_id = json.dig("data", "id")

      set_birth_date("1992-01-01")

      expect(run_json(run_id).dig("slots", "first_year")).to eq(1990)
    end

    it "starts from a fixed first year without a Birth Date" do
      start(slots(1990, 1999))

      expect(response).to have_http_status(:created)
      expect(json.dig("data", "slots")).to include("first_year" => 1990, "last_year" => 1999, "growing" => false)
      expect(json.dig("data", "slots", "years").map { |slot| slot["year"] }).to eq((1990..1999).to_a)
      expect(json.dig("data", "progress")).to eq("in_progress" => 0, "cleared" => 0, "target" => 10,
        "caught_up" => false)
      expect(json.dig("meta", "notices")).to eq([])
    end

    it "refuses a birth-year Run when the birth year comes after the last year" do
      set_birth_date("2001-02-03")

      start(slots(nil, 1999))

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("error")).to eq("no_slots")
    end
  end

  # A game first released in `first` (a year), and in each of `also` in some
  # region or on some platform.
  def game(title, first, *also)
    create(:game, title: title, initial_release_date: Time.utc(first, 6, 1)).tap do |created|
      also.each { |year| create(:release, game: created, release_date: Time.utc(year, 3, 1)) }
    end
  end

  def log_completion(game, on: "2026-10-15")
    post "/api/v1/users/#{member.user_id}/completions",
      params: { data: { gamedb_game_id: game.game_id, completion_type: "Main Story", completed_at: on } },
      headers: auth_headers_for(member), as: :json
    expect(response).to have_http_status(:created)
    json.dig("data", "completion_id")
  end

  def start_playing(game)
    post "/api/v1/users/#{member.user_id}/now_playing", params: { data: { gamedb_game_id: game.game_id } },
      headers: auth_headers_for(member), as: :json
    expect(response).to have_http_status(:created)
  end

  # The Run's filled slots, as year => title.
  def filled(run_id)
    run_json(run_id).dig("slots", "years").select { |slot| slot["game_id"] }.to_h { |slot| slot.values_at("year", "title") }
  end

  def entries(run_id)
    run_json(run_id).fetch("entries").to_h { |entry| [ entry["title"], entry.values_at("state", "slot_year") ] }
  end

  describe "filling slots" do
    it "fills the earliest open year a Cleared game fits, counting its regional release years" do
      run_id = start_run(slots(1994, 1999))
      ff7 = game("Final Fantasy VII", 1997)
      # Released in Japan in 1997 and in the West in 1998.
      tactics = game("Final Fantasy Tactics", 1997, 1998)
      suikoden = game("Suikoden", 1995, 1996)
      xenogears = game("Xenogears", 1998)

      log_completion(ff7)
      log_completion(tactics)
      log_completion(suikoden)
      log_completion(xenogears)

      expect(filled(run_id)).to eq(1995 => "Suikoden", 1997 => "Final Fantasy VII", 1998 => "Final Fantasy Tactics")
      expect(entries(run_id)).to include("Xenogears" => [ "cleared", nil ])
      expect(run_json(run_id).fetch("progress")).to eq("in_progress" => 0, "cleared" => 3, "target" => 6,
        "caught_up" => false)
    end

    it "fills one slot per game, and moves on to its next year when the earliest is taken" do
      run_id = start_run(slots(1995, 1999))
      log_completion(game("Suikoden", 1995))
      log_completion(game("Chrono Trigger", 1995, 1996, 2008))

      expect(filled(run_id)).to eq(1995 => "Suikoden", 1996 => "Chrono Trigger")
    end

    it "lists In Progress games without a slot, and leaves out games that fit none of the years" do
      run_id = start_run(slots(1995, 1999))
      start_playing(game("Suikoden II", 1998))
      log_completion(game("Persona 5", 2016))

      expect(entries(run_id)).to eq("Suikoden II" => [ "in_progress", nil ])
      expect(run_json(run_id).dig("progress", "in_progress")).to eq(1)
    end

    it "gives a freed year to a Cleared game waiting for one" do
      run_id = start_run(slots(1995, 1999))
      suikoden = log_completion(game("Suikoden", 1995))
      log_completion(game("Chrono Trigger", 1995))
      expect(filled(run_id)).to eq(1995 => "Suikoden")

      delete "/api/v1/completions/#{suikoden}", headers: auth_headers_for(member)

      expect(filled(run_id)).to eq(1995 => "Chrono Trigger")
    end
  end

  describe "reading a Slots Run" do
    it "gives each entry its game's release years and cover, and the Challenge's range on the Run" do
      run_id = start_run(slots(1995, 1999, counts_past_play: true))
      chrono = game("Chrono Trigger", 1995, 1999, 2008)
      create(:game_image, :primary, game: chrono)
      log_completion(chrono)
      start_playing(game("Suikoden II", 1998))

      run = run_json(run_id)

      expect(run.fetch("challenge")).to include("counts_past_play" => true,
        "slots" => { "first_year" => 1995, "last_year" => 1999, "counts_past_play" => true })
      expect(run.fetch("entries").map { |entry| entry.values_at("title", "release_years", "cover_url") }).to eq([
        [ "Chrono Trigger", [ 1995, 1999, 2008 ], chrono.reload.cover_url ],
        [ "Suikoden II", [ 1998 ], nil ]
      ])
    end
  end

  describe "moving a game to another year" do
    let(:challenge) { slots(1995, 1999) }
    let!(:run_id) { start_run(challenge) }
    let!(:chrono) { game("Chrono Trigger", 1995, 1999) }
    let!(:suikoden) { game("Suikoden", 1995) }
    let!(:xenogears) { game("Xenogears", 1998) }

    def move(game, year, as: auth_headers_for(member))
      post "/api/v1/challenge_runs/#{run_id}/slot_move", params: { data: { game_id: game.game_id, slot_year: year } },
        headers: as, as: :json
    end

    it "moves a game to another open year it fits, freeing its slot for a game waiting for one" do
      log_completion(chrono)
      log_completion(suikoden)
      expect(filled(run_id)).to eq(1995 => "Chrono Trigger")

      move(chrono, 1999)

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "entries")).to include(a_hash_including("title" => "Chrono Trigger", "slot_year" => 1999,
        "picked_by_hand" => true))
      expect(filled(run_id)).to eq(1995 => "Suikoden", 1999 => "Chrono Trigger")
    end

    it "keeps the move when the member logs more games" do
      log_completion(chrono)
      move(chrono, 1999)

      log_completion(suikoden)
      log_completion(game("Chrono Cross", 1999))

      expect(filled(run_id)).to eq(1995 => "Suikoden", 1999 => "Chrono Trigger")
    end

    it "refuses a year the game doesn't fit, a filled year and a year outside the Run" do
      log_completion(chrono)
      log_completion(xenogears)

      move(chrono, 1997)
      expect(response).to have_http_status(:unprocessable_content)
      expect(json).to include("error" => "slot_not_fitting")
      expect(json.fetch("message")).to include("Chrono Trigger", "1997")

      move(xenogears, 1995)
      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("error")).to eq("slot_not_fitting")

      log_completion(game("Chrono Cross", 1999))
      move(chrono, 1999)
      expect(response).to have_http_status(:conflict)
      expect(json.fetch("error")).to eq("slot_filled")
      expect(json.fetch("message")).to include("Chrono Cross")

      move(chrono, 2005)
      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("error")).to eq("slot_out_of_range")

      expect(filled(run_id)).to eq(1995 => "Chrono Trigger", 1998 => "Xenogears", 1999 => "Chrono Cross")
    end

    it "refuses a game that isn't Cleared on the Run, another member, and a Run that isn't Active" do
      start_playing(suikoden)
      move(suikoden, 1995)
      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("error")).to eq("not_cleared")

      log_completion(chrono)
      move(chrono, 1999, as: auth_headers_for(create(:user)))
      expect(response).to have_http_status(:forbidden)

      post "/api/v1/challenge_runs/#{run_id}/abandon", headers: auth_headers_for(member), as: :json
      move(chrono, 1999)
      expect(response).to have_http_status(:conflict)
      expect(json.fetch("error")).to eq("run_not_active")
    end

    it "is refused for a Pool Run" do
      pool_run = create(:challenge_run, user: member)

      post "/api/v1/challenge_runs/#{pool_run.id}/slot_move", params: { data: { game_id: chrono.game_id, slot_year: 1995 } },
        headers: auth_headers_for(member), as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("error")).to eq("not_slots")
    end

    it "lets the bot move for the member it names" do
      log_completion(chrono)

      post "/api/v1/challenge_runs/#{run_id}/slot_move",
        params: { data: { acting_user_id: member.user_id, game_id: chrono.game_id, slot_year: 1999 } },
        headers: service_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(filled(run_id)).to eq(1999 => "Chrono Trigger")
    end
  end

  describe "Finished and Caught Up" do
    def announcements = BotJob.where(kind: "challenge_announce").order(:id)

    it "Finishes a fixed-range Run when every slot is Cleared, and announces it" do
      run_id = start_run(slots(1995, 1996, name: "Two Years"))
      log_completion(game("Suikoden", 1995))
      expect(run_json(run_id)).to include("status" => "active")

      expect { log_completion(game("Tobal No. 1", 1996)) }.to change(announcements, :count).by(1)

      run = run_json(run_id)
      expect(run).to include("status" => "finished")
      expect(run.fetch("progress")).to eq("in_progress" => 0, "cleared" => 2, "target" => 2, "caught_up" => false)
      expect(announcements.last.payload).to include("event" => "run_finished")
    end

    it "keeps a Finished Run's slots after a Game Completion is deleted" do
      run_id = start_run(slots(1995, 1995))
      completion_id = log_completion(game("Suikoden", 1995))
      log_completion(game("Chrono Trigger", 1995))

      delete "/api/v1/completions/#{completion_id}", headers: auth_headers_for(member)

      expect(run_json(run_id)).to include("status" => "finished")
      expect(filled(run_id)).to eq(1995 => "Suikoden")
    end

    it "is Caught Up while every year so far is Cleared, announced once, and never Finishes" do
      run_id = start_run(slots(2024, nil, name: "Recent Years"))
      log_completion(game("Unicorn Overlord", 2024))
      log_completion(game("Clair Obscur", 2025))
      expect(run_json(run_id).dig("progress", "caught_up")).to be(false)

      ballad = game("Ballad of the Thirteenth", 2026)
      completion_id = nil
      expect { completion_id = log_completion(ballad) }.to change(announcements, :count).by(1)

      run = run_json(run_id)
      expect(run).to include("status" => "active")
      expect(run.fetch("progress")).to eq("in_progress" => 0, "cleared" => 3, "target" => 3, "caught_up" => true)
      job = announcements.last
      expect(job.payload).to include("event" => "run_caught_up", "feature_key" => "challenges")
      expect(job.payload.dig("challenge", "name")).to eq("Recent Years")
      expect(job.payload.dig("run", "progress")).to include("caught_up" => true)
      expect(job.payload.dig("run", "user", "user_id")).to eq(member.user_id)
      expect(job.summary).to include("Caught Up", "Recent Years")

      # Losing and regaining it in the same year announces nothing more.
      expect do
        delete "/api/v1/completions/#{completion_id}", headers: auth_headers_for(member)
        expect(run_json(run_id).dig("progress", "caught_up")).to be(false)
        log_completion(ballad)
      end.not_to change(announcements, :count)
      expect(run_json(run_id).dig("progress", "caught_up")).to be(true)
    end

    it "stops being Caught Up when the new year's slot opens on 1 January, and is announced again once filled" do
      run_id = start_run(slots(2025, nil))
      log_completion(game("Clair Obscur", 2025))
      log_completion(game("Ballad of the Thirteenth", 2026))
      expect(run_json(run_id).dig("progress", "caught_up")).to be(true)

      travel_to(Time.zone.parse("2026-12-31 23:59:00 -05:00"))
      expect(run_json(run_id).dig("progress", "caught_up")).to be(true)

      travel_to(Time.zone.parse("2027-01-01 00:00:00 -05:00"))
      run = run_json(run_id)
      expect(run.fetch("progress")).to eq("in_progress" => 0, "cleared" => 2, "target" => 3, "caught_up" => false)
      expect(run.dig("slots", "years").last).to eq("year" => 2027, "game_id" => nil, "title" => nil)

      expect { log_completion(game("A 2027 Game", 2027), on: "2027-01-01") }.to change(announcements, :count).by(1)
      expect(run_json(run_id).dig("progress", "caught_up")).to be(true)
    end

    it "is never Caught Up once the Run is no longer Active" do
      run_id = start_run(slots(2026, nil))
      log_completion(game("Ballad of the Thirteenth", 2026))

      post "/api/v1/challenge_runs/#{run_id}/abandon", headers: auth_headers_for(member), as: :json

      expect(run_json(run_id).dig("progress", "caught_up")).to be(false)
    end
  end
end
