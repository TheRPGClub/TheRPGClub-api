# frozen_string_literal: true

require "rails_helper"

# Secret Santa's timed side up to the draw (spec #376, "Lifecycle job" and
# "Secret Santa draw"; ticket #383): Editions open by themselves from the
# Challenge's calendar, sign-up is announced when it opens, 3 days before the
# cutoff and at close, and at the cutoff the draw leaves out members below
# the backlog minimum and puts the rest in one circle with a Run each. The
# lifecycle job runs under a frozen clock in the club's time zone, and what
# it did is read back through the API and the bot jobs it queued.
RSpec.describe "api/v1/challenge edition lifecycle behavior", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:moderator) { create(:user, role_member: true, role_moderator: true) }

  before do
    set_feature_flag("challenges", "live")
    Challenges::SweepSchedule.clear
  end

  after { Challenges::SweepSchedule.clear }

  def club_time(text) = ActiveSupport::TimeZone[Challenges::TIME_ZONE].parse(text)

  # Runs the job at `club_time`, a time in the club's time zone.
  def tick(text)
    travel_to(club_time(text)) { Challenges::LifecycleJob.perform_now }
  end

  def announcements(event) = BotJob.where(kind: "challenge_announce").order(:id).select { |job| job.payload["event"] == event }

  def dms = BotJob.where(kind: "challenge_dm").order(:id).to_a

  # Secret Santa with the default calendar (cutoff 1 December, pick deadline
  # 15 December, reveal 25 December), created after the 2025 cutoff, so its
  # first Edition, 2026, opens on 26 December 2025.
  def create_santa(at: "2025-12-10 12:00", **data)
    travel_to(club_time(at)) do
      post "/api/v1/challenges", headers: auth_headers_for(moderator), as: :json, params: { data: {
        name: "Secret Santa", challenge_format: "assignment", schedule: "always_open", hosted_by_club: true
      }.merge(data) }
      expect(response).to have_http_status(:created)
      json.dig("data", "id")
    end
  end

  def editions(challenge_id, at:)
    travel_to(club_time(at)) do
      get "/api/v1/challenges/#{challenge_id}/editions", headers: auth_headers_for(moderator)
      json.fetch("data")
    end
  end

  def member_with_backlog(games)
    user = create(:user, role_member: true)
    create_list(:backlog_entry, games, user: user)
    user
  end

  def sign_up(edition_id, user, at: "2026-11-10 12:00")
    travel_to(club_time(at)) do
      post "/api/v1/challenge_editions/#{edition_id}/signup", headers: auth_headers_for(user), as: :json
      expect(response).to have_http_status(:ok)
    end
  end

  describe "Editions opening" do
    it "opens the next Edition the day after the reveal, and announces its sign-up once" do
      santa = create_santa

      tick("2025-12-25 23:59")
      expect(editions(santa, at: "2025-12-25 23:59")).to be_empty

      tick("2025-12-26 00:01")
      tick("2025-12-26 00:02")
      Challenges::SweepSchedule.clear
      tick("2025-12-26 09:00")

      edition = editions(santa, at: "2025-12-26 09:00").sole
      expect(edition).to include("year" => 2026, "phase" => "signup", "signup_opens_on" => "2025-12-26",
        "signup_cutoff_on" => "2026-12-01", "reveal_on" => "2026-12-25", "ends_on" => "2027-12-25")
      job = announcements("signup_opened").sole
      expect(job.payload).to include("feature_key" => "challenges")
      expect(job.payload.dig("challenge", "name")).to eq("Secret Santa")
      expect(job.payload.fetch("edition")).to include("id" => edition["id"], "year" => 2026)

      tick("2026-12-26 00:01")

      expect(editions(santa, at: "2026-12-26 00:01").map { |row| [ row["year"], row["signup_opens_on"] ] })
        .to eq([ [ 2027, "2026-12-26" ], [ 2026, "2025-12-26" ] ])
      expect(announcements("signup_opened").map { |row| row.payload.dig("edition", "year") }).to eq([ 2026, 2027 ])
    end

    it "does not announce an Edition that opened with its Challenge, whose creation was announced" do
      create_santa(at: "2026-11-02 12:00")

      tick("2026-11-02 12:01")

      expect(announcements("challenge_created").size).to eq(1)
      expect(announcements("signup_opened")).to be_empty
    end

    it "does not announce a hidden Challenge's sign-up" do
      santa = create_santa
      Challenge.find(santa).update!(hidden: true)

      tick("2025-12-26 00:01")

      expect(editions(santa, at: "2025-12-26 00:01").size).to eq(1)
      expect(announcements("signup_opened")).to be_empty
    end
  end

  describe "sign-up closing soon" do
    it "is announced once, 3 days before the cutoff" do
      santa = create_santa
      tick("2025-12-26 00:01")
      edition_id = editions(santa, at: "2025-12-26 00:01").sole["id"]
      sign_up(edition_id, member_with_backlog(5))

      tick("2026-11-27 23:59")
      expect(announcements("signup_closing")).to be_empty

      tick("2026-11-28 00:01")
      tick("2026-11-28 00:02")
      Challenges::SweepSchedule.clear
      tick("2026-11-29 12:00")

      job = announcements("signup_closing").sole
      expect(job.payload).to include("days_left" => 3)
      expect(job.payload.fetch("edition")).to include("id" => edition_id, "signup_cutoff_on" => "2026-12-01",
        "signed_up_count" => 1)
    end
  end

  describe "the draw at the cutoff" do
    let!(:santa) { create_santa }
    let(:edition_id) do
      tick("2025-12-26 00:01")
      editions(santa, at: "2025-12-26 00:01").sole["id"]
    end

    it "draws the signed-up members into one circle with a Run each, and announces how many joined, once" do
      members = Array.new(4) { member_with_backlog(5) }
      members.each { |user| sign_up(edition_id, user) }

      tick("2026-11-30 23:59")
      expect(announcements("signup_closed")).to be_empty

      tick("2026-12-01 00:01")
      tick("2026-12-01 00:02")
      Challenges::SweepSchedule.clear
      tick("2026-12-01 09:00")

      edition = editions(santa, at: "2026-12-01 09:00").sole
      expect(edition).to include("phase" => "picking", "signed_up_count" => 4)
      expect(edition.fetch("members")).to all(include("left_out" => false))

      runs = travel_to(club_time("2026-12-01 09:00")) do
        get "/api/v1/challenges/#{santa}/runs", headers: auth_headers_for(moderator)
        json.fetch("data")
      end
      expect(runs.map { |run| run.dig("user", "user_id") }).to match_array(members.map(&:user_id))
      expect(runs).to all(include("status" => "active", "edition" => { "id" => edition_id, "year" => 2026 },
        "window" => { "starts_on" => "2026-12-25", "ends_on" => "2027-12-24" }))

      circle = ChallengeEditionSignup.where(edition_id: edition_id).pluck(:user_id, :recipient_user_id).to_h
      expect(circle.values).to match_array(circle.keys)
      expect(circle).to(be_none { |santa_id, recipient_id| santa_id == recipient_id })
      start = circle.keys.first
      loop_members = [ start ]
      loop_members << circle[loop_members.last] until circle[loop_members.last] == start
      expect(loop_members.size).to eq(4)

      job = announcements("signup_closed").sole
      expect(job.payload).to include("joined" => 4, "left_out" => 0)
      expect(job.payload.to_json).not_to include("recipient")
    end

    it "leaves out and DMs members who fell below 5 backlog games, even with Challenge DMs off" do
      drawn = Array.new(2) { member_with_backlog(5) }
      shrunk = member_with_backlog(5)
      [ *drawn, shrunk ].each { |user| sign_up(edition_id, user) }
      UserGameBacklog.where(user_id: shrunk.user_id).limit(2).each(&:destroy!)
      shrunk.update!(challenge_dms: false)

      tick("2026-12-01 00:01")

      edition = editions(santa, at: "2026-12-01 00:01").sole
      expect(edition.fetch("members").to_h { |row| [ row["user_id"], row["left_out"] ] })
        .to eq(drawn.to_h { |user| [ user.user_id, false ] }.merge(shrunk.user_id => true))
      expect(ChallengeRun.where(edition_id: edition_id).pluck(:user_id)).to match_array(drawn.map(&:user_id))

      dm = dms.sole
      expect(dm.payload).to include("event" => "left_out_of_draw", "user_id" => shrunk.user_id,
        "feature_key" => "challenges", "backlog_count" => 3, "minimum" => 5)
      expect(dm.payload.fetch("edition")).to include("id" => edition_id, "year" => 2026)
      expect(announcements("signup_closed").sole.payload).to include("joined" => 2, "left_out" => 1)
    end

    it "cancels an Edition with fewer than 2 members left, with no Runs, and announces it" do
      sign_up(edition_id, member_with_backlog(5))
      left_out = member_with_backlog(5)
      sign_up(edition_id, left_out)
      UserGameBacklog.where(user_id: left_out.user_id).first.destroy!

      tick("2026-12-01 00:01")
      tick("2026-12-01 00:02")

      expect(editions(santa, at: "2026-12-01 00:02").sole).to include("phase" => "cancelled")
      expect(ChallengeRun.where(challenge_id: santa)).to be_empty
      expect(announcements("signup_closed")).to be_empty
      expect(announcements("edition_cancelled").sole.payload).to include("joined" => 1, "left_out" => 1)
      expect(dms.map { |job| job.payload["user_id"] }).to eq([ left_out.user_id ])

      tick("2026-12-26 00:01")
      expect(editions(santa, at: "2026-12-26 00:01").first).to include("year" => 2027, "phase" => "signup")
    end

    it "draws a member into the next Edition while their Run of the last one is still Active" do
      members = Array.new(2) { member_with_backlog(5) }
      members.each { |user| sign_up(edition_id, user) }
      tick("2026-12-01 00:01")

      tick("2026-12-26 00:01")
      next_edition = editions(santa, at: "2026-12-26 00:01").first
      members.each { |user| sign_up(next_edition["id"], user, at: "2027-11-10 12:00") }
      tick("2027-12-01 00:01")

      runs = ChallengeRun.where(challenge_id: santa, status: "active")
      expect(runs.group(:user_id).count).to eq(members.to_h { |user| [ user.user_id, 2 ] })
      expect(runs.distinct.pluck(:edition_id)).to contain_exactly(edition_id, next_edition["id"])
    end

    it "cancels an Edition nobody signed up for" do
      edition_id

      tick("2026-12-01 00:01")

      expect(editions(santa, at: "2026-12-01 00:01").sole).to include("phase" => "cancelled")
      expect(announcements("edition_cancelled").sole.payload).to include("joined" => 0, "left_out" => 0)
    end
  end
end
