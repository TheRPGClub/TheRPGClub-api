# frozen_string_literal: true

require "rails_helper"

# Run progress (spec #376, ticket #378; docs/adr/0009): a Pool Run fills in by
# itself from the member's Game Completions and Now Playing, whichever
# endpoint or import wrote them.
RSpec.describe "api/v1/challenge run progress behavior", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:member) { create(:user, role_member: true) }
  let(:franchise) { create(:franchise, name: "Final Fantasy") }
  let!(:ff7) { create(:game, title: "Final Fantasy VII") }
  let!(:ff8) { create(:game, title: "Final Fantasy VIII") }
  let!(:ff9) { create(:game, title: "Final Fantasy IX") }
  let!(:outside) { create(:game, title: "Chrono Trigger") }

  before { [ ff7, ff8, ff9 ].each { |game| GamedbGameFranchise.create!(game: game, franchise: franchise) } }

  # Mid-October 2026 in the club's time zone.
  around { |example| travel_to(Time.zone.parse("2026-10-15 12:00:00 -04:00")) { example.run } }

  # A Pool Challenge of the Final Fantasy franchise. The factory also puts
  # one game of its own in the Pool by hand.
  def pool_challenge(target: 2, **attrs)
    create(:challenge, pool_target: target, **attrs).tap do |challenge|
      ChallengePoolFranchise.create!(challenge: challenge, franchise: franchise)
    end
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

  def log_completion(game, on:)
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
    json.dig("data", "entry_id")
  end

  def entries(run_id) = run_json(run_id).fetch("entries").map { |entry| entry.values_at("title", "state") }

  describe "Now Playing" do
    it "makes a Pool game In Progress, and removing it from Now Playing takes that away" do
      run_id = start_run(pool_challenge)

      entry_id = start_playing(ff7)
      start_playing(outside)

      expect(run_json(run_id).fetch("progress")).to eq("in_progress" => 1, "cleared" => 0, "target" => 2)
      expect(entries(run_id)).to eq([ [ "Final Fantasy VII", "in_progress" ] ])

      delete "/api/v1/now_playing/#{entry_id}", headers: auth_headers_for(member)
      expect(response).to have_http_status(:ok)

      expect(run_json(run_id).fetch("progress")).to include("in_progress" => 0)
      expect(entries(run_id)).to eq([])
    end

    it "counts what the member is already playing when the Run starts" do
      start_playing(ff8)

      run_id = start_run(pool_challenge)

      expect(entries(run_id)).to eq([ [ "Final Fantasy VIII", "in_progress" ] ])
    end
  end

  describe "Game Completions" do
    it "Clears a Pool game logged inside the window, in place of In Progress" do
      run_id = start_run(pool_challenge)
      start_playing(ff7)

      completion_id = log_completion(ff7, on: "2026-10-15")
      log_completion(outside, on: "2026-10-15")

      run = run_json(run_id)
      expect(run.fetch("progress")).to eq("in_progress" => 0, "cleared" => 1, "target" => 2)
      expect(run.fetch("entries")).to eq([
        { "game_id" => ff7.game_id, "title" => "Final Fantasy VII", "state" => "cleared",
          "cleared_on" => "2026-10-15", "completion_id" => completion_id, "slot_year" => nil,
          "picked_by_hand" => false, "cover_url" => nil, "release_years" => nil }
      ])
    end

    it "follows an edited date out of the window and back, and a deleted Game Completion" do
      run_id = start_run(pool_challenge)
      completion_id = log_completion(ff7, on: "2026-10-15")

      patch "/api/v1/completions/#{completion_id}", params: { data: { completed_at: "2026-10-01" } },
        headers: auth_headers_for(member), as: :json
      expect(response).to have_http_status(:ok)
      expect(run_json(run_id).dig("progress", "cleared")).to eq(0)

      patch "/api/v1/completions/#{completion_id}", params: { data: { completed_at: "2026-10-16" } },
        headers: auth_headers_for(member), as: :json
      expect(run_json(run_id).dig("progress", "cleared")).to eq(1)

      delete "/api/v1/completions/#{completion_id}", headers: auth_headers_for(member)
      expect(response).to have_http_status(:ok)
      expect(run_json(run_id).dig("progress", "cleared")).to eq(0)
    end

    it "never counts a Game Completion without a date" do
      run_id = start_run(pool_challenge)

      post "/api/v1/users/#{member.user_id}/completions",
        params: { data: { gamedb_game_id: ff7.game_id, completion_type: "Main Story" } },
        headers: auth_headers_for(member), as: :json
      patch "/api/v1/completions/#{json.dig('data', 'completion_id')}", params: { data: { completed_at: nil } },
        headers: auth_headers_for(member), as: :json
      expect(response).to have_http_status(:ok)

      expect(run_json(run_id).dig("progress", "cleared")).to eq(0)
    end

    it "counts one game toward each of the member's Runs it fits" do
      fall = start_run(pool_challenge)
      other = start_run(create(:challenge).tap { |c| ChallengePoolGame.create!(challenge: c, game: ff9, inclusion: "include") })

      log_completion(ff9, on: "2026-10-15")

      expect(run_json(fall).dig("progress", "cleared")).to eq(1)
      expect(run_json(other).dig("progress", "cleared")).to eq(1)
    end

    it "leaves the member's Runs alone when only a note or completion type changes" do
      start_run(pool_challenge)
      completion_id = log_completion(ff7, on: "2026-10-15")
      entry_id = start_playing(ff8)
      allow(Challenges).to receive(:refresh_runs!).and_call_original

      patch "/api/v1/completions/#{completion_id}", params: { data: { note: "Gold Saucer", completion_type: "Completionist" } },
        headers: auth_headers_for(member), as: :json
      expect(response).to have_http_status(:ok)
      patch "/api/v1/now_playing/#{entry_id}", params: { data: { note: "Disc 2" } },
        headers: auth_headers_for(member), as: :json
      expect(response).to have_http_status(:ok)

      expect(Challenges).not_to have_received(:refresh_runs!)
    end

    it "leaves Runs that have ended alone" do
      run_id = start_run(pool_challenge)
      post "/api/v1/challenge_runs/#{run_id}/abandon", headers: auth_headers_for(member), as: :json

      log_completion(ff7, on: "2026-10-15")

      expect(run_json(run_id)).to include("status" => "abandoned", "entries" => [])
    end
  end

  describe "the window" do
    it "runs from an Always Open Run's start day: the day before does not count" do
      run_id = start_run(pool_challenge)

      log_completion(ff7, on: "2026-10-14")
      expect(run_json(run_id).dig("progress", "cleared")).to eq(0)

      log_completion(ff8, on: "2026-10-15")
      expect(entries(run_id)).to eq([ [ "Final Fantasy VIII", "cleared" ] ])
    end

    it "is the current Season for a Seasonal Run: its first and last day count, the day before does not" do
      travel_to(Time.zone.parse("2026-09-01 12:00:00 -04:00"))
      run_id = start_run(pool_challenge(target: 3, schedule: "seasonal", season_start_month: 6, season_start_day: 21,
        season_end_month: 9, season_end_day: 22))

      log_completion(ff7, on: "2026-06-20")
      expect(run_json(run_id).fetch("window")).to eq("starts_on" => "2026-06-21", "ends_on" => "2026-09-22")
      expect(run_json(run_id).dig("progress", "cleared")).to eq(0)

      log_completion(ff8, on: "2026-06-21")
      log_completion(ff9, on: "2026-09-22")
      log_completion(ff7, on: "2026-09-23")

      expect(entries(run_id)).to eq([ [ "Final Fantasy VIII", "cleared" ], [ "Final Fantasy IX", "cleared" ] ])
    end

    it "counts play from earlier in the Season when a member joins late, Finishing at once if it is enough" do
      travel_to(Time.zone.parse("2026-09-01 12:00:00 -04:00"))
      log_completion(ff7, on: "2026-07-01")
      challenge = pool_challenge(target: 1, schedule: "seasonal", season_start_month: 6, season_start_day: 21,
        season_end_month: 9, season_end_day: 22)

      run_id = start_run(challenge)

      expect(run_json(run_id)).to include("status" => "finished")
    end
  end

  describe "Finishing" do
    it "Finishes the Run when its Cleared games reach the target, and queues a run_finished announcement" do
      run_id = start_run(pool_challenge(name: "Fall of Final Fantasy"))
      log_completion(ff7, on: "2026-10-15")
      expect(run_json(run_id)).to include("status" => "active", "ended_at" => nil)

      expect { log_completion(ff8, on: "2026-10-15") }
        .to change { BotJob.where(kind: "challenge_announce").count }.by(1)

      run = run_json(run_id)
      expect(run).to include("status" => "finished")
      expect(run.fetch("ended_at")).to be_present
      expect(run.fetch("progress")).to eq("in_progress" => 0, "cleared" => 2, "target" => 2)

      job = BotJob.where(kind: "challenge_announce").last
      expect(job.requested_by_user_id).to eq(member.user_id)
      expect(job.payload).to include("event" => "run_finished", "feature_key" => "challenges")
      expect(job.payload.dig("challenge", "name")).to eq("Fall of Final Fantasy")
      expect(job.payload.fetch("run")).to include("id" => run_id, "status" => "finished")
      expect(job.payload.dig("run", "user", "user_id")).to eq(member.user_id)
      expect(job.payload.dig("run", "progress")).to eq("in_progress" => 0, "cleared" => 2, "target" => 2)
    end

    it "announces a Finished Run only once" do
      start_run(pool_challenge(target: 1))

      expect do
        log_completion(ff7, on: "2026-10-15")
        log_completion(ff8, on: "2026-10-15")
      end.to change { BotJob.where(kind: "challenge_announce").count }.by(1)
    end

    it "announces a member Finishing a Seasonal Challenge once per Season, even after they delete the Run" do
      challenge = pool_challenge(target: 1, schedule: "seasonal", season_start_month: 9, season_start_day: 22,
        season_end_month: 12, season_end_day: 20)
      first = start_run(challenge)
      expect { log_completion(ff7, on: "2026-10-15") }
        .to change { BotJob.where(kind: "challenge_announce").count }.by(1)

      delete "/api/v1/challenge_runs/#{first}", headers: auth_headers_for(member)
      expect(response).to have_http_status(:ok)

      expect { expect(run_json(start_run(challenge))).to include("status" => "finished") }
        .not_to(change { BotJob.where(kind: "challenge_announce").count })
    end

    it "announces a Finished Always Open Run again after the member deletes it and Finishes a new one" do
      challenge = pool_challenge(target: 1)
      first = start_run(challenge)
      log_completion(ff7, on: "2026-10-15")
      delete "/api/v1/challenge_runs/#{first}", headers: auth_headers_for(member)

      expect { expect(run_json(start_run(challenge))).to include("status" => "finished") }
        .to change { BotJob.where(kind: "challenge_announce").count }.by(1)
    end

    it "stays Finished, with its Cleared games, after a Game Completion is deleted" do
      run_id = start_run(pool_challenge(target: 1))
      completion_id = log_completion(ff7, on: "2026-10-15")
      expect(run_json(run_id)).to include("status" => "finished")

      delete "/api/v1/completions/#{completion_id}", headers: auth_headers_for(member)

      run = run_json(run_id)
      expect(run).to include("status" => "finished")
      expect(run.fetch("progress")).to include("cleared" => 1)
      expect(run.dig("entries", 0)).to include("title" => "Final Fantasy VII", "state" => "cleared",
        "completion_id" => nil)
    end

    it "Finishes a Run of a hidden Challenge without announcing it" do
      challenge = pool_challenge(target: 1)
      run_id = start_run(challenge)
      challenge.update!(hidden: true)

      expect { log_completion(ff7, on: "2026-10-15") }.not_to(change { BotJob.where(kind: "challenge_announce").count })

      expect(run_json(run_id)).to include("status" => "finished")
    end

    it "keeps counting games Cleared past the target" do
      run_id = start_run(pool_challenge(target: 1))
      log_completion(ff7, on: "2026-10-15")

      log_completion(ff8, on: "2026-10-16")

      expect(run_json(run_id)).to include("status" => "finished")
      expect(run_json(run_id).dig("progress", "cleared")).to eq(2)
    end

    it "takes every game in the Pool as the target \"all\"" do
      challenge = pool_challenge(target: nil)
      run_id = start_run(challenge)
      [ ff7, ff8, ff9 ].each { |game| log_completion(game, on: "2026-10-15") }

      expect(run_json(run_id)).to include("status" => "active")
      expect(run_json(run_id).fetch("progress")).to include("cleared" => 3, "target" => 4)

      log_completion(challenge.pool_games.sole.game, on: "2026-10-15")
      expect(run_json(run_id)).to include("status" => "finished")
    end
  end

  describe "the Completionator import" do
    let(:import) { create(:completionator_import, user: member) }

    it "Clears a Pool game the import adds, and follows an updated date" do
      run_id = start_run(pool_challenge)
      row = create(:completionator_import_item, import: import, game_title: ff7.title, gamedb_game_id: ff7.game_id)

      post "/api/v1/completionator_import_items/#{row.id}/add_completion",
        params: { data: { completion_type: "Main Story", platform_id: nil, completed_at: "2026-10-15" } },
        headers: auth_headers_for(member), as: :json
      expect(response).to have_http_status(:ok)
      expect(entries(run_id)).to eq([ [ "Final Fantasy VII", "cleared" ] ])

      update = create(:completionator_import_item, import: import, game_title: ff7.title, gamedb_game_id: ff7.game_id,
        completion_id: row.reload.completion_id, completed_at: Time.utc(2026, 10, 1))
      post "/api/v1/completionator_import_items/#{update.id}/update_completion", params: { data: { fields: [ "date" ] } },
        headers: auth_headers_for(member), as: :json
      expect(response).to have_http_status(:ok)
      expect(entries(run_id)).to eq([])
    end

    it "never Clears from a row with no date, though the database dates it today first" do
      run_id = start_run(pool_challenge(target: 1))
      row = create(:completionator_import_item, import: import, game_title: ff7.title, gamedb_game_id: ff7.game_id)

      post "/api/v1/completionator_import_items/#{row.id}/add_completion",
        params: { data: { completion_type: "Main Story", platform_id: nil } },
        headers: auth_headers_for(member), as: :json
      expect(response).to have_http_status(:ok)

      expect(run_json(run_id)).to include("status" => "active", "entries" => [])
    end
  end

  describe "a member's Runs" do
    it "lists their Runs, current and past, with progress" do
      finished = create(:challenge_run, user: member, status: "finished", started_at: 1.year.ago)
      run_id = start_run(pool_challenge)
      start_playing(ff7)

      get "/api/v1/users/#{member.user_id}/challenge_runs", headers: auth_headers_for(create(:user))

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data").map { |run| run.values_at("id", "status") })
        .to eq([ [ run_id, "active" ], [ finished.id, "finished" ] ])
      expect(json.dig("data", 0, "progress")).to eq("in_progress" => 1, "cleared" => 0, "target" => 2)

      get "/api/v1/users/#{member.user_id}/challenge_runs", params: { status: "finished" }, headers: service_headers
      expect(json.fetch("data").map { |run| run["id"] }).to eq([ finished.id ])
    end

    it "lists a Challenge's Runs with progress" do
      challenge = pool_challenge
      run_id = start_run(challenge)

      get "/api/v1/challenges/#{challenge.id}/runs", headers: service_headers

      expect(json.fetch("data").map { |run| run["id"] }).to eq([ run_id ])
      expect(json.dig("data", 0, "progress")).to include("target" => 2)
    end

    it "leaves out another member's view the Runs of a hidden Challenge, but not the member's own" do
      run = create(:challenge_run, user: member, challenge: create(:challenge, hidden: true))

      get "/api/v1/users/#{member.user_id}/challenge_runs", headers: auth_headers_for(create(:user))
      expect(json.fetch("data")).to eq([])

      get "/api/v1/users/#{member.user_id}/challenge_runs", headers: auth_headers_for(member)
      expect(json.fetch("data").map { |row| row["id"] }).to eq([ run.id ])
    end
  end
end
