# frozen_string_literal: true

require "rails_helper"

# The timed side of Challenges (spec #376, "Lifecycle job"; ticket #379):
# Seasons open and close by themselves and Runs Expire when their time is
# up. The lifecycle job runs under a frozen clock in the club's time zone
# (America/New_York), and what it did is read back through the API and the
# bot jobs it queued.
RSpec.describe "api/v1/challenge lifecycle behavior", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:member) { create(:user, role_member: true) }

  before { Challenges::SweepSchedule.clear }
  after { Challenges::SweepSchedule.clear }

  # Runs the job at `club_time`, a time in the club's time zone.
  def tick(club_time)
    travel_to(club_time(club_time)) { Challenges::LifecycleJob.perform_now }
  end

  def club_time(text) = ActiveSupport::TimeZone[Challenges::TIME_ZONE].parse(text)

  def announcements(event) = BotJob.where(kind: "challenge_announce").select { |job| job.payload["event"] == event }

  # A Seasonal Challenge created before its Season, so its opening is news.
  def seasonal(season, **attrs)
    travel_to(club_time("2026-01-02 12:00")) { create(:challenge, :seasonal, season: season, **attrs) }
  end

  describe "a Season opening" do
    it "queues one Season opened announcement on its first day, even when the job runs twice" do
      challenge = seasonal("06-21..09-22", name: "Summer of Suikoden")

      tick("2026-06-20 23:59")
      expect(announcements("season_opened")).to be_empty

      tick("2026-06-21 00:01")
      tick("2026-06-21 00:02")
      Challenges::SweepSchedule.clear
      tick("2026-06-21 09:00")

      job = announcements("season_opened").sole
      expect(job.payload).to include("feature_key" => "challenges",
        "season" => { "starts_on" => "2026-06-21", "ends_on" => "2026-09-22" })
      expect(job.payload.fetch("challenge")).to include("id" => challenge.id, "name" => "Summer of Suikoden",
        "open" => true)
    end

    it "announces a Season the job missed while it is still Open, and again the next year" do
      seasonal("06-21..09-22")

      tick("2026-07-04 12:00")
      tick("2027-06-21 00:01")

      expect(announcements("season_opened").map { |job| job.payload.dig("season", "starts_on") })
        .to eq(%w[2026-06-21 2027-06-21])
    end

    it "does not announce a Season that was already Open when its Challenge was created" do
      travel_to(club_time("2026-07-01 12:00")) { create(:challenge, :seasonal, season: "06-21..09-22") }

      tick("2026-07-01 12:01")

      expect(announcements("season_opened")).to be_empty
    end

    it "does not announce a hidden Challenge's Season" do
      seasonal("06-21..09-22", hidden: true)

      tick("2026-06-21 00:01")

      expect(announcements("season_opened")).to be_empty
    end
  end

  describe "a Season crossing the new year" do
    it "opens on its first day in December and Expires its Runs the day after it ends in February" do
      challenge = seasonal("12-01..02-28", name: "Winter of Wild Arms")

      tick("2026-11-30 23:59")
      expect(announcements("season_opened")).to be_empty

      tick("2026-12-01 00:01")
      expect(announcements("season_opened").sole.payload.fetch("season"))
        .to eq("starts_on" => "2026-12-01", "ends_on" => "2027-02-28")

      run_id = travel_to(club_time("2026-12-10 12:00")) { start_run(challenge) }

      tick("2027-02-28 23:59")
      expect(run_json(run_id)).to include("status" => "active")

      tick("2027-03-01 00:01")
      run = run_json(run_id)
      expect(run).to include("status" => "expired", "window" => { "starts_on" => "2026-12-01", "ends_on" => "2027-02-28" })
      expect(run.fetch("ended_at")).to be_present
    end
  end

  describe "a Season ending" do
    it "Expires its Active Runs the day after its last day, leaving Finished and Abandoned Runs alone" do
      challenge = seasonal("06-21..09-22")
      finisher = create(:user, role_member: true)
      quitter = create(:user, role_member: true)
      active, finished, abandoned = travel_to(club_time("2026-07-01 12:00")) do
        [ start_run(challenge), start_run(challenge, as: finisher), start_run(challenge, as: quitter) ]
      end
      travel_to(club_time("2026-07-02 12:00")) do
        log_completion(finisher, challenge.pool_games.first.game, on: "2026-07-02")
        post "/api/v1/challenge_runs/#{abandoned}/abandon", headers: auth_headers_for(quitter), as: :json
      end

      tick("2026-09-22 23:59")
      expect(run_json(active)).to include("status" => "active")

      tick("2026-09-23 00:01")
      tick("2026-09-23 00:02")

      expect(run_json(active)).to include("status" => "expired")
      expect(run_json(finished, as: finisher)).to include("status" => "finished")
      expect(run_json(abandoned, as: quitter)).to include("status" => "abandoned")
    end
  end

  describe "the Season ending reminder" do
    def dms = BotJob.where(kind: "challenge_dm").order(:id).to_a

    it "DMs each member with an unFinished Run 7 days before the Season ends, once, unless they opted out" do
      challenge = seasonal("06-21..09-22", name: "Summer of Suikoden")
      finisher = create(:user, role_member: true)
      opted_out = create(:user, role_member: true)
      quitter = create(:user, role_member: true)
      reminded, _finished, _opted_out, abandoned = travel_to(club_time("2026-07-01 12:00")) do
        [ member, finisher, opted_out, quitter ].map { |user| start_run(challenge, as: user) }
      end
      travel_to(club_time("2026-07-02 12:00")) do
        log_completion(finisher, challenge.pool_games.first.game, on: "2026-07-02")
        patch "/api/v1/users/#{opted_out.user_id}/challenge_settings", params: { data: { dms: false } },
          headers: auth_headers_for(opted_out), as: :json
        expect(response).to have_http_status(:ok)
        post "/api/v1/challenge_runs/#{abandoned}/abandon", headers: auth_headers_for(quitter), as: :json
      end

      tick("2026-09-14 23:59")
      expect(dms).to be_empty

      tick("2026-09-15 00:01")
      tick("2026-09-15 00:02")
      Challenges::SweepSchedule.clear
      tick("2026-09-16 12:00")

      job = dms.sole
      expect(job.payload).to include("event" => "season_ending", "feature_key" => "challenges",
        "user_id" => member.user_id, "days_left" => 7,
        "season" => { "starts_on" => "2026-06-21", "ends_on" => "2026-09-22" })
      expect(job.payload.fetch("run")).to include("id" => reminded, "status" => "active")
      expect(job.payload.dig("challenge", "name")).to eq("Summer of Suikoden")
    end

    it "is sent on a late tick with the days actually left" do
      challenge = seasonal("06-21..09-22")
      travel_to(club_time("2026-07-01 12:00")) { start_run(challenge) }

      tick("2026-09-20 08:00")

      expect(dms.sole.payload).to include("days_left" => 2)
    end

    it "is not sent for a Season that ended before the job looked" do
      challenge = seasonal("06-21..09-22")
      travel_to(club_time("2026-07-01 12:00")) { start_run(challenge) }

      tick("2026-09-23 00:01")

      expect(dms).to be_empty
    end
  end

  describe "an Always Open Challenge's end date" do
    it "Expires its Active Runs the day after it, and Closes it for good" do
      challenge = travel_to(club_time("2026-10-01 12:00")) { create(:challenge, ends_on: Date.new(2026, 10, 31)) }
      finisher = create(:user, role_member: true)
      active, finished = travel_to(club_time("2026-10-02 12:00")) do
        [ start_run(challenge), start_run(challenge, as: finisher) ]
      end
      travel_to(club_time("2026-10-03 12:00")) do
        log_completion(finisher, challenge.pool_games.first.game, on: "2026-10-03")
      end

      tick("2026-10-31 23:59")
      expect(run_json(active)).to include("status" => "active")

      tick("2026-11-01 00:01")
      tick("2026-11-01 00:02")

      expect(run_json(active)).to include("status" => "expired")
      expect(run_json(finished, as: finisher)).to include("status" => "finished")

      host = challenge.host
      travel_to(club_time("2026-11-02 12:00")) do
        patch "/api/v1/challenges/#{challenge.id}", params: { data: { ends_on: "2026-12-31" } },
          headers: auth_headers_for(host), as: :json
        expect(response).to have_http_status(:unprocessable_content)
        expect(json.fetch("message")).to include("Closed for good")

        get "/api/v1/challenges/#{challenge.id}", headers: auth_headers_for(member)
        expect(json.fetch("data")).to include("open" => false, "ends_on" => "2026-10-31")
        expect(json.dig("data", "ended_at")).to be_present
      end
    end

    it "leaves a Challenge whose end date moved later Open" do
      challenge = travel_to(club_time("2026-10-01 12:00")) { create(:challenge, ends_on: Date.new(2026, 10, 31)) }
      run_id = travel_to(club_time("2026-10-02 12:00")) { start_run(challenge) }
      tick("2026-10-02 12:01")

      travel_to(club_time("2026-10-30 12:00")) do
        patch "/api/v1/challenges/#{challenge.id}", params: { data: { ends_on: "2026-12-31" } },
          headers: auth_headers_for(challenge.host), as: :json
        expect(response).to have_http_status(:ok)
      end
      tick("2026-11-01 00:01")

      expect(run_json(run_id)).to include("status" => "active")
    end
  end

  def log_completion(user, game, on:)
    post "/api/v1/users/#{user.user_id}/completions",
      params: { data: { gamedb_game_id: game.game_id, completion_type: "Main Story", completed_at: on } },
      headers: auth_headers_for(user), as: :json
    expect(response).to have_http_status(:created)
  end

  def start_run(challenge, as: member)
    post "/api/v1/challenges/#{challenge.id}/runs", headers: auth_headers_for(as), as: :json
    expect(response).to have_http_status(:created)
    json.dig("data", "id")
  end

  def run_json(run_id, as: member)
    get "/api/v1/challenge_runs/#{run_id}", headers: auth_headers_for(as)
    json.fetch("data")
  end
end
