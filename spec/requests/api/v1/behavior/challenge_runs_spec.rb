# frozen_string_literal: true

require "rails_helper"

# Runs (spec #376, ticket #378): starting, abandoning and deleting a Run of a
# Pool Challenge, and reading a member's Runs.
RSpec.describe "api/v1/challenge runs behavior", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:member) { create(:user, role_member: true) }
  let(:other) { create(:user, role_member: true) }
  let(:challenge) { create(:challenge, name: "Fall of Final Fantasy") }

  # Mid-October 2026 in the club's time zone.
  around { |example| travel_to(Time.zone.parse("2026-10-15 12:00:00 -04:00")) { example.run } }

  def start_run(challenge, as: member)
    post "/api/v1/challenges/#{challenge.id}/runs", headers: auth_headers_for(as), as: :json
  end

  def abandon(run_id, as: member)
    post "/api/v1/challenge_runs/#{run_id}/abandon", headers: auth_headers_for(as), as: :json
  end

  def delete_run(run_id, as: member)
    delete "/api/v1/challenge_runs/#{run_id}", headers: auth_headers_for(as)
  end

  describe "starting a Run" do
    it "starts an Active Run of an Open Challenge for the member" do
      start_run(challenge)

      expect(response).to have_http_status(:created)
      expect(json.fetch("data")).to include(
        "status" => "active", "ended_at" => nil,
        "window" => { "starts_on" => "2026-10-15", "ends_on" => nil },
        "progress" => { "in_progress" => 0, "cleared" => 0, "target" => 1 }, "entries" => []
      )
      expect(json.dig("data", "challenge")).to include("id" => challenge.id, "name" => "Fall of Final Fantasy")
      expect(json.dig("data", "user", "user_id")).to eq(member.user_id)
    end

    it "refuses a Closed Challenge" do
      start_run(create(:challenge, :seasonal, season: "06-21..09-22"))

      expect(response).to have_http_status(:conflict)
      expect(json).to include("error" => "challenge_closed")
      expect(json.fetch("message")).to include("Closed")
    end

    it "refuses an Always Open Challenge past its end date" do
      start_run(create(:challenge, ends_on: Date.new(2026, 10, 14)))

      expect(response).to have_http_status(:conflict)
      expect(json).to include("error" => "challenge_closed")
    end

    it "refuses a second Active Run of the same Challenge, but allows Runs of other Challenges" do
      start_run(challenge)
      first = json.dig("data", "id")

      start_run(challenge)

      expect(response).to have_http_status(:conflict)
      expect(json).to include("error" => "run_active", "run_id" => first)

      start_run(create(:challenge))
      expect(response).to have_http_status(:created)
    end

    it "lets another member start their own Run of the same Challenge" do
      start_run(challenge)
      start_run(challenge, as: other)

      expect(response).to have_http_status(:created)
    end

    it "allows starting again after the last Run was Finished or Abandoned" do
      create(:challenge_run, challenge: challenge, user: member, status: "finished")
      start_run(challenge)
      expect(response).to have_http_status(:created)

      abandon(json.dig("data", "id"))
      start_run(challenge)
      expect(response).to have_http_status(:created)
    end

    it "gives a Seasonal Run the current Season as its window, across the new year" do
      travel_to(Time.zone.parse("2027-01-10 12:00:00 -05:00"))
      start_run(create(:challenge, :seasonal, season: "12-01..02-28"))

      expect(response).to have_http_status(:created)
      expect(json.dig("data", "window")).to eq("starts_on" => "2026-12-01", "ends_on" => "2027-02-28")
    end

    it "allows one Run of a Seasonal Challenge per Season, Finished or Abandoned" do
      seasonal = create(:challenge, :seasonal, season: "09-22..12-20")
      finished = create(:challenge_run, challenge: seasonal, user: member, status: "finished",
        season_starts_on: Date.new(2026, 9, 22), season_ends_on: Date.new(2026, 12, 20))

      start_run(seasonal)

      expect(response).to have_http_status(:conflict)
      expect(json).to include("error" => "season_run_exists", "run_id" => finished.id)
      expect(json.fetch("message")).to include("Season")

      finished.update!(status: "abandoned")
      start_run(seasonal)
      expect(response).to have_http_status(:conflict)
      expect(json).to include("error" => "season_run_exists", "run_id" => finished.id)
    end

    it "allows a new Run of a Seasonal Challenge in a later Season" do
      seasonal = create(:challenge, :seasonal, season: "09-22..12-20")
      create(:challenge_run, challenge: seasonal, user: member, status: "finished",
        season_starts_on: Date.new(2025, 9, 22), season_ends_on: Date.new(2025, 12, 20))

      start_run(seasonal)

      expect(response).to have_http_status(:created)
      expect(json.dig("data", "window")).to eq("starts_on" => "2026-09-22", "ends_on" => "2026-12-20")
    end

    it "does not find a hidden Challenge for a member" do
      start_run(create(:challenge, hidden: true))

      expect(response).to have_http_status(:not_found)
    end

    it "starts a Run for the member the bot names, and needs one" do
      post "/api/v1/challenges/#{challenge.id}/runs", params: { data: { acting_user_id: member.user_id } },
        headers: service_headers, as: :json

      expect(response).to have_http_status(:created)
      expect(json.dig("data", "user", "user_id")).to eq(member.user_id)

      post "/api/v1/challenges/#{challenge.id}/runs", params: { data: {} }, headers: service_headers, as: :json
      expect(response).to have_http_status(:bad_request)
    end

    it "is refused while the Feature is in Preview for a member who is not an Admin" do
      set_feature_flag("challenges", "preview")

      start_run(challenge)
      expect(response).to have_http_status(:not_found)

      post "/api/v1/challenges/#{challenge.id}/runs", params: { data: { acting_user_id: member.user_id } },
        headers: service_headers, as: :json
      expect(response).to have_http_status(:forbidden)
      expect(json).to include("error" => "feature_unavailable")
    end
  end

  describe "abandoning a Run" do
    it "makes the member's Active Run Abandoned and keeps it" do
      start_run(challenge)
      run_id = json.dig("data", "id")

      abandon(run_id)

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("id" => run_id, "status" => "abandoned")
      expect(json.dig("data", "ended_at")).to be_present

      get "/api/v1/users/#{member.user_id}/challenge_runs", headers: auth_headers_for(member)
      expect(json.fetch("data").map { |run| run.values_at("id", "status") }).to eq([ [ run_id, "abandoned" ] ])
    end

    it "refuses a Run that is not Active" do
      run = create(:challenge_run, challenge: challenge, user: member, status: "finished")

      abandon(run.id)

      expect(response).to have_http_status(:conflict)
      expect(json).to include("error" => "run_not_active")
    end

    it "refuses another member's Run" do
      run = create(:challenge_run, challenge: challenge, user: member)

      abandon(run.id, as: other)

      expect(response).to have_http_status(:forbidden)
      expect(json.fetch("message")).to include("your own")
    end

    it "abandons for the member the bot names, and only their own Run" do
      run = create(:challenge_run, challenge: challenge, user: member)

      post "/api/v1/challenge_runs/#{run.id}/abandon", params: { data: { acting_user_id: other.user_id } },
        headers: service_headers, as: :json
      expect(response).to have_http_status(:forbidden)

      post "/api/v1/challenge_runs/#{run.id}/abandon", params: { data: { acting_user_id: member.user_id } },
        headers: service_headers, as: :json
      expect(response).to have_http_status(:ok)
    end
  end

  describe "deleting a Run" do
    it "deletes the member's Abandoned, Finished and Expired Runs" do
      runs = %w[abandoned finished expired].map do |status|
        create(:challenge_run, challenge: create(:challenge), user: member, status: status)
      end

      runs.each do |run|
        delete_run(run.id)
        expect(response).to have_http_status(:ok)
        expect(json.fetch("data")).to eq("id" => run.id, "deleted" => true)
      end

      get "/api/v1/users/#{member.user_id}/challenge_runs", headers: auth_headers_for(member)
      expect(json.fetch("data")).to eq([])
    end

    it "refuses an Active Run, which must be abandoned first" do
      run = create(:challenge_run, challenge: challenge, user: member)

      delete_run(run.id)

      expect(response).to have_http_status(:conflict)
      expect(json).to include("error" => "run_active")
      expect(json.fetch("message")).to include("Abandon")
    end

    it "refuses another member's Run" do
      run = create(:challenge_run, challenge: challenge, user: member, status: "abandoned")

      delete_run(run.id, as: other)

      expect(response).to have_http_status(:forbidden)
    end

    it "deletes for the member the bot names in the query" do
      run = create(:challenge_run, challenge: challenge, user: member, status: "abandoned")

      delete "/api/v1/challenge_runs/#{run.id}", params: { acting_user_id: member.user_id }, headers: service_headers
      expect(response).to have_http_status(:ok)
    end
  end

  describe "reading Runs" do
    it "gives each entry its game's title and cover, and no Slots fields on a Pool Run" do
      covered = create(:game, title: "Chrono Trigger").tap { |game| create(:game_image, :primary, game: game) }
      plain = create(:game, title: "Suikoden")
      run = create(:challenge_run, challenge: challenge, user: member)
      ChallengeRunEntry.create!(run: run, game: covered, state: "cleared", cleared_on: Date.new(2026, 10, 1))
      ChallengeRunEntry.create!(run: run, game: plain, state: "in_progress")

      get "/api/v1/users/#{member.user_id}/challenge_runs", headers: auth_headers_for(member)

      listed = json.fetch("data").sole
      expect(listed.fetch("entries").map { |entry| entry.values_at("title", "cover_url", "release_years") }).to eq([
        [ "Chrono Trigger", covered.cover_url, nil ], [ "Suikoden", nil, nil ]
      ])
      expect(listed.fetch("challenge")).to include("counts_past_play" => false, "slots" => nil)
    end

    it "names each member with their Discord avatar and the stored avatar image's path" do
      member.update!(discord_avatar: "a1b2c3")
      challenge.host.update!(discord_avatar: nil)
      run = create(:challenge_run, challenge: challenge, user: member)

      get "/api/v1/challenge_runs/#{run.id}", headers: auth_headers_for(member)

      expect(json.dig("data", "user")).to eq(
        "user_id" => member.user_id, "username" => member.username, "global_name" => member.global_name,
        "discord_avatar" => "a1b2c3", "avatar_url" => "/api/v1/users/#{member.user_id}/avatar"
      )

      get "/api/v1/challenges/#{challenge.id}", headers: auth_headers_for(member)

      expect(json.dig("data", "host")).to include("user_id" => challenge.host_user_id, "discord_avatar" => nil,
        "avatar_url" => "/api/v1/users/#{challenge.host_user_id}/avatar")
    end
  end
end
