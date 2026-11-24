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

    it "carries last Season's Finishers, the Pool's first games and the key art and tint for the post" do
      challenge = seasonal("06-21..09-22")
      cover = create(:game_image, :primary)
      ChallengePoolGame.create!(challenge: challenge, game: cover.game, inclusion: "optional")
      alice, bob, carol, dave = create_list(:user, 4, role_member: true)
      season = ->(year) { { season_starts_on: Date.new(year, 6, 21), season_ends_on: Date.new(year, 9, 22) } }
      create(:challenge_run, challenge: challenge, user: carol, status: "finished", ended_at: Time.utc(2026, 8, 1),
        **season.(2026))
      create(:challenge_run, challenge: challenge, user: alice, status: "finished", ended_at: Time.utc(2026, 7, 1),
        **season.(2026))
      create(:challenge_run, challenge: challenge, user: bob, status: "expired", **season.(2026))
      create(:challenge_run, challenge: challenge, user: dave, status: "finished", **season.(2025))

      tick("2027-06-21 00:01")

      payload = announcements("season_opened").sole.payload
      expect(payload.fetch("last_season_finishers")).to eq([ alice, carol ].map do |user|
        { "user_id" => user.user_id, "username" => user.username, "global_name" => user.global_name,
          "discord_avatar" => nil, "avatar_url" => "/api/v1/users/#{user.user_id}/avatar" }
      end)
      expect(payload.fetch("pool_games").size).to eq(2)
      expect(payload.dig("pool_games", 0)).to eq("game_id" => cover.game_id, "title" => cover.game.title,
        "cover_url" => cover.url)
      expect(payload.fetch("challenge")).to include("key_art_url" => cover.url,
        "tint" => { "fill" => challenge.reload.tint_fill, "hi" => challenge.tint_hi })
    end

    it "carries no Finishers for a Challenge's first Season" do
      seasonal("06-21..09-22")

      tick("2026-06-21 00:01")

      expect(announcements("season_opened").sole.payload.fetch("last_season_finishers")).to eq([])
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

  describe "the new year's slot" do
    # A game first released in `first` and again in each of `also`.
    def game(title, first, *also)
      create(:game, title: title, initial_release_date: Time.utc(first, 6, 1)).tap do |created|
        also.each { |year| create(:release, game: created, release_date: Time.utc(year, 3, 1)) }
      end
    end

    def slots_of(run_id) = run_json(run_id).dig("slots", "years").to_h { |slot| slot.values_at("year", "title") }

    it "fills on 1 January with a Cleared game waiting for it, Catching the Run Up again, once" do
      challenge = travel_to(club_time("2026-10-01 12:00")) do
        create(:challenge, challenge_format: "slots", slots_first_year: 2025, slots_last_year: nil)
      end
      run_id = travel_to(club_time("2026-10-02 12:00")) do
        start_run(challenge).tap do
          log_completion(member, game("Clair Obscur", 2025), on: "2026-10-02")
          log_completion(member, game("Ballad of the Thirteenth", 2026), on: "2026-10-02")
          # Out in Japan in 2026 and in the West in 2027: it waits for 2027.
          log_completion(member, game("Lantern Isles", 2026, 2027), on: "2026-10-02")
        end
      end
      expect(announcements("run_caught_up").size).to eq(1)

      tick("2026-12-31 23:59")
      tick("2027-01-01 00:01")
      tick("2027-01-01 00:02")
      Challenges::SweepSchedule.clear
      tick("2027-01-01 09:00")

      travel_to(club_time("2027-01-01 09:01")) do
        expect(slots_of(run_id)).to eq(2025 => "Clair Obscur", 2026 => "Ballad of the Thirteenth",
          2027 => "Lantern Isles")
        expect(run_json(run_id).dig("progress", "caught_up")).to be(true)
      end
      expect(announcements("run_caught_up").size).to eq(2)
    end

    it "is due again only on the next 1 January" do
      travel_to(club_time("2026-10-01 12:00")) do
        create(:challenge, challenge_format: "slots", slots_first_year: 2025, slots_last_year: nil)
      end

      tick("2026-10-01 12:01")

      expect(Challenges::Lifecycle.next_event_at(now: club_time("2026-10-01 12:02"))).to eq(club_time("2027-01-01 00:00"))
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
