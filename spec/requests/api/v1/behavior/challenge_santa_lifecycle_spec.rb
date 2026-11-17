# frozen_string_literal: true

require "rails_helper"

# Secret Santa from the draw to the Edition's end (spec #376, "Lifecycle job"
# and "Secret Santa draw"; ticket #384): the pick reminder 2 days before the
# deadline, random picks at the deadline for Santas who missed it, withdrew
# or left, the reveal, the year to Clear the assigned game, and the Runs
# Expiring when the Edition ends on the next reveal date. The lifecycle job
# runs under a frozen clock in the club's time zone, and what it did is read
# back through the API and the bot jobs it queued.
RSpec.describe "api/v1/challenge santa lifecycle behavior", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:moderator) { create(:user, role_member: true, role_moderator: true) }

  before do
    set_feature_flag("challenges", "live")
    Challenges::SweepSchedule.clear
  end

  after { Challenges::SweepSchedule.clear }

  def club_time(text) = ActiveSupport::TimeZone[Challenges::TIME_ZONE].parse(text)

  def tick(text)
    travel_to(club_time(text)) { Challenges::LifecycleJob.perform_now }
  end

  def announcements(event) = BotJob.where(kind: "challenge_announce").order(:id).select { |job| job.payload["event"] == event }

  def dms(event) = BotJob.where(kind: "challenge_dm").order(:id).select { |job| job.payload["event"] == event }

  # Secret Santa with the default calendar: the 2026 Edition opens on 26
  # December 2025, is drawn on 1 December 2026, takes picks until the start
  # of 15 December, is revealed on 25 December and ends on 25 December 2027.
  let(:santa_challenge) do
    travel_to(club_time("2025-12-10 12:00")) do
      post "/api/v1/challenges", headers: auth_headers_for(moderator), as: :json, params: { data: {
        name: "Secret Santa", challenge_format: "assignment", schedule: "always_open", hosted_by_club: true
      } }
      json.dig("data", "id")
    end
  end

  let!(:edition_id) do
    santa_challenge
    tick("2025-12-26 00:01")
    ChallengeEdition.find_by!(challenge_id: santa_challenge).id
  end

  let(:alice) { member_with_backlog("Chrono Trigger", "Earthbound", "Mother 3", "Okami", "Xenogears") }
  let(:bob) { member_with_backlog("Baldur's Gate", "Planescape", "Fallout", "Arcanum", "Torment") }

  def member_with_backlog(*titles)
    user = create(:user, role_member: true)
    titles.each { |title| create(:backlog_entry, user: user, game: create(:game, title: title)) }
    user
  end

  def backlog_game(user, title) = UserGameBacklog.where(user_id: user.user_id).joins(:game).find_by!(gamedb_games: { title: title }).game

  def draw(*members)
    members.each do |user|
      travel_to(club_time("2026-11-10 12:00")) do
        post "/api/v1/challenge_editions/#{edition_id}/signup", headers: auth_headers_for(user), as: :json
        expect(response).to have_http_status(:ok)
      end
    end
    tick("2026-12-01 00:01")
  end

  # The Santa (a member of a circle of `members`) giving to `recipient`.
  def santa_of(recipient, members)
    members.find do |user|
      travel_to(club_time("2026-12-05 12:00")) do
        get "/api/v1/challenge_editions/#{edition_id}/santa", headers: auth_headers_for(user)
        response.ok? && json.dig("data", "recipient", "user_id") == recipient.user_id
      end
    end
  end

  def pick(game, as:, at: "2026-12-05 12:00")
    travel_to(club_time(at)) do
      put "/api/v1/challenge_editions/#{edition_id}/santa/pick", headers: auth_headers_for(as), as: :json,
        params: { data: { game_id: game.game_id } }
      expect(response).to have_http_status(:ok)
    end
  end

  def edition(as: moderator, at: "2026-12-26 12:00")
    travel_to(club_time(at)) do
      get "/api/v1/challenge_editions/#{edition_id}", headers: auth_headers_for(as)
      json.fetch("data")
    end
  end

  def run_of(user, as: user, at: "2026-12-26 12:00")
    travel_to(club_time(at)) do
      get "/api/v1/users/#{user.user_id}/challenge_runs", headers: auth_headers_for(as)
      json.fetch("data").find { |run| run.dig("edition", "id") == edition_id }
    end
  end

  describe "the pick reminder" do
    it "DMs the Santas who haven't picked, once, 2 days before the deadline" do
      draw(alice, bob)
      pick(backlog_game(bob, "Fallout"), as: alice)

      tick("2026-12-12 23:59")
      expect(dms("pick_reminder")).to be_empty

      tick("2026-12-13 00:01")
      tick("2026-12-13 00:02")
      Challenges::SweepSchedule.clear
      tick("2026-12-14 12:00")

      dm = dms("pick_reminder").sole
      expect(dm.payload).to include("user_id" => bob.user_id, "feature_key" => "challenges", "days_left" => 2,
        "recipient" => include("user_id" => alice.user_id))
      expect(dm.payload.fetch("edition")).to include("id" => edition_id, "pick_deadline_on" => "2026-12-15")
    end

    it "skips Santas who turned Challenge DMs off, left the server or withdrew" do
      carol = member_with_backlog("A", "B", "C", "D", "E")
      dave = member_with_backlog("F", "G", "H", "I", "J")
      draw(alice, bob, carol, dave)
      alice.update!(challenge_dms: false)
      bob.update!(server_left_at: Time.current)
      travel_to(club_time("2026-12-05 12:00")) do
        delete "/api/v1/challenge_editions/#{edition_id}/signup", headers: auth_headers_for(carol)
      end

      tick("2026-12-13 00:01")

      expect(dms("pick_reminder").map { |job| job.payload["user_id"] }).to eq([ dave.user_id ])
    end
  end

  describe "random picks at the deadline" do
    # Clears every game of the member's backlog but `title`, years ago, so
    # `title` is the only game a Santa may pick for them.
    def leave_eligible(user, title)
      UserGameBacklog.where(user_id: user.user_id).preload(:game).each do |entry|
        next if entry.game.title == title

        create(:completion, user: user, game: entry.game, completed_at: Time.utc(2019, 5, 1))
      end
    end

    def assignments(at: "2026-12-15 12:00")
      edition(at: at).fetch("assignments").to_h { |row| [ row.dig("recipient", "user_id"), row ] }
    end

    it "keeps the Santas' picks and picks at random for the others from the eligible backlog, once" do
      draw(alice, bob)
      pick(backlog_game(bob, "Fallout"), as: alice)
      leave_eligible(alice, "Okami")

      tick("2026-12-14 23:59")
      expect(assignments(at: "2026-12-14 23:59").dig(alice.user_id, "game")).to be_nil

      tick("2026-12-15 00:01")
      first = assignments
      tick("2026-12-15 00:02")
      Challenges::SweepSchedule.clear
      tick("2026-12-15 12:00")

      expect(assignments).to eq(first)
      expect(first.fetch(bob.user_id)).to include("picked_randomly" => false,
        "game" => include("title" => "Fallout"), "santa" => include("user_id" => alice.user_id))
      expect(first.fetch(alice.user_id)).to include("picked_randomly" => true,
        "game" => include("title" => "Okami"), "santa" => include("user_id" => bob.user_id))
    end

    it "picks at random for the recipients of Santas who withdrew or left the server without picking, without redrawing" do
      carol = member_with_backlog("Ico", "Rez", "Vib-Ribbon", "Jet Set Radio", "Shenmue")
      members = [ alice, bob, carol ]
      draw(*members)
      members.each { |user| leave_eligible(user, { alice => "Okami", bob => "Torment", carol => "Rez" }[user]) }
      withdrawn = santa_of(alice, members)
      departed = santa_of(bob, members)
      picker = santa_of(carol, members)
      pick(backlog_game(carol, "Rez"), as: picker)
      travel_to(club_time("2026-12-05 12:00")) do
        delete "/api/v1/challenge_editions/#{edition_id}/signup", headers: auth_headers_for(withdrawn)
      end
      departed.update!(server_left_at: Time.current)

      tick("2026-12-15 00:01")

      rows = assignments
      expect(rows.fetch(alice.user_id)).to include("picked_randomly" => true, "game" => include("title" => "Okami"),
        "santa" => include("user_id" => withdrawn.user_id))
      expect(rows.fetch(bob.user_id)).to include("picked_randomly" => true, "game" => include("title" => "Torment"))
      expect(rows.fetch(carol.user_id)).to include("picked_randomly" => false)
    end

    it "keeps the pick of a Santa who left the server after picking" do
      draw(alice, bob)
      pick(backlog_game(bob, "Fallout"), as: alice)
      leave_eligible(alice, "Okami")
      alice.update!(server_left_at: Time.current)

      tick("2026-12-15 00:01")

      expect(assignments.fetch(bob.user_id)).to include("picked_randomly" => false, "game" => include("title" => "Fallout"))
      expect(assignments.fetch(alice.user_id)).to include("picked_randomly" => true, "game" => include("title" => "Okami"))
    end

    it "picks a game in the recipient's Now Playing when it is the only one left" do
      draw(alice, bob)
      leave_eligible(alice, "Okami")
      create(:now_playing_entry, user: alice, game: backlog_game(alice, "Okami"))
      pick(backlog_game(bob, "Fallout"), as: alice)

      tick("2026-12-15 00:01")

      expect(assignments.dig(alice.user_id, "game", "title")).to eq("Okami")
    end
  end

  describe "the reveal" do
    let(:member) { create(:user, role_member: true) }

    before do
      draw(alice, bob)
      pick(backlog_game(bob, "Fallout"), as: alice)
      pick(backlog_game(alice, "Okami"), as: bob)
    end

    it "reveals every assignment on the reveal date, without the Santas, and announces it once" do
      tick("2026-12-24 23:59")
      expect(edition(as: member, at: "2026-12-24 23:59")).to include("phase" => "picking", "assignments" => nil)
      expect(announcements("edition_revealed")).to be_empty

      tick("2026-12-25 00:01")
      tick("2026-12-25 00:02")
      Challenges::SweepSchedule.clear
      tick("2026-12-25 12:00")

      shown = edition(as: member)
      expect(shown).to include("phase" => "revealed")
      expect(shown.fetch("assignments").map { |row| [ row.dig("recipient", "user_id"), row.dig("game", "title") ] })
        .to contain_exactly([ alice.user_id, "Okami" ], [ bob.user_id, "Fallout" ])
      expect(shown.fetch("assignments")).to all(include("santa" => nil, "picked_randomly" => false,
        "run" => include("status" => "active", "progress" => { "in_progress" => 0, "cleared" => 0, "target" => 1 })))

      job = announcements("edition_revealed").sole
      expect(job.payload).to include("feature_key" => "challenges")
      expect(job.payload.dig("edition", "assignments").map { |row| row.dig("game", "title") })
        .to contain_exactly("Okami", "Fallout")
      expect(job.payload.dig("edition", "assignments")).to all(include("santa" => nil))
    end

    it "makes the assigned game the recipient's Run goal, kept secret until then" do
      create(:now_playing_entry, user: bob, game: backlog_game(bob, "Fallout"))
      tick("2026-12-24 12:00")
      expect(run_of(bob, at: "2026-12-24 12:00")).to include("entries" => [],
        "assignment" => { "game" => nil, "picked_randomly" => nil, "santa" => nil })

      tick("2026-12-25 00:01")

      run = run_of(bob)
      expect(run.fetch("assignment")).to include("game" => include("title" => "Fallout"), "picked_randomly" => false,
        "santa" => nil)
      expect(run.fetch("entries")).to contain_exactly(include("title" => "Fallout", "state" => "in_progress"))
      expect(run.fetch("progress")).to eq("in_progress" => 1, "cleared" => 0, "target" => 1)
    end

    it "does not announce a hidden Challenge's reveal" do
      Challenge.find(santa_challenge).update!(hidden: true)

      tick("2026-12-25 00:01")

      expect(edition).to include("phase" => "revealed")
      expect(announcements("edition_revealed")).to be_empty
    end
  end

  describe "the year to Clear" do
    let(:member) { create(:user, role_member: true) }

    before do
      draw(alice, bob)
      pick(backlog_game(bob, "Fallout"), as: alice)
      pick(backlog_game(alice, "Okami"), as: bob)
      tick("2026-12-25 00:01")
    end

    def log_completion(user, game, on:)
      travel_to(club_time("#{on} 12:00")) do
        post "/api/v1/users/#{user.user_id}/completions", headers: auth_headers_for(user), as: :json,
          params: { data: { gamedb_game_id: game.game_id, completion_type: "Main Story", completed_at: on } }
        expect(response).to have_http_status(:created)
      end
    end

    it "Finishes the Run when the assigned game is Cleared inside the Edition, even once it left the backlog" do
      fallout = backlog_game(bob, "Fallout")
      UserGameBacklog.where(user_id: bob.user_id, gamedb_game_id: fallout.game_id).destroy_all

      log_completion(bob, fallout, on: "2027-12-24")

      expect(run_of(bob, at: "2027-12-24 13:00")).to include("status" => "finished",
        "progress" => { "in_progress" => 0, "cleared" => 1, "target" => 1 })
      expect(announcements("run_finished").map { |job| job.payload.dig("run", "user", "user_id") })
        .to eq([ bob.user_id ])
    end

    it "does not count a Game Completion from before the reveal, nor of another game" do
      log_completion(bob, backlog_game(bob, "Fallout"), on: "2026-12-20")
      log_completion(bob, backlog_game(bob, "Torment"), on: "2027-01-10")

      expect(run_of(bob, at: "2027-01-10 13:00")).to include("status" => "active",
        "progress" => { "in_progress" => 0, "cleared" => 0, "target" => 1 })
    end

    it "Expires the unFinished Runs when the Edition ends on the next reveal date, then shows the Santas" do
      log_completion(alice, backlog_game(alice, "Okami"), on: "2027-03-01")

      tick("2027-12-24 23:59")
      expect(run_of(bob, at: "2027-12-24 23:59")).to include("status" => "active")
      expect(edition(as: member, at: "2027-12-24 23:59").fetch("assignments")).to all(include("santa" => nil))
      expect(run_of(bob, as: member, at: "2027-12-24 23:59").dig("assignment", "santa")).to be_nil

      tick("2027-12-25 00:01")
      tick("2027-12-25 00:02")

      expect(run_of(bob, at: "2027-12-25 12:00")).to include("status" => "expired",
        "window" => { "starts_on" => "2026-12-25", "ends_on" => "2027-12-24" })
      expect(run_of(alice, at: "2027-12-25 12:00")).to include("status" => "finished")
      shown = edition(as: member, at: "2027-12-25 12:00")
      expect(shown).to include("phase" => "ended")
      expect(shown.fetch("assignments").to_h { |row| [ row.dig("recipient", "user_id"), row.dig("santa", "user_id") ] })
        .to eq(alice.user_id => bob.user_id, bob.user_id => alice.user_id)
      expect(run_of(bob, as: member, at: "2027-12-25 12:00").dig("assignment", "santa", "user_id"))
        .to eq(alice.user_id)
    end
  end

  describe "the Santa's identity before the Edition ends" do
    let(:member) { create(:user, role_member: true) }

    it "is served to staff only" do
      draw(alice, bob)
      pick(backlog_game(bob, "Fallout"), as: alice)
      tick("2026-12-25 00:01")

      expect(edition(as: member).fetch("assignments")).to all(include("santa" => nil))
      expect(run_of(bob).dig("assignment", "santa")).to be_nil
      expect(run_of(bob, as: member).dig("assignment", "santa")).to be_nil
      travel_to(club_time("2026-12-26 12:00")) do
        get "/api/v1/challenges/#{santa_challenge}/runs", headers: auth_headers_for(member)
      end
      expect(json.fetch("data").map { |run| run.dig("assignment", "santa") }).to all(be_nil)

      expect(edition(as: moderator).fetch("assignments").map { |row| row.dig("santa", "user_id") })
        .to contain_exactly(alice.user_id, bob.user_id)
      expect(run_of(bob, as: moderator).dig("assignment", "santa", "user_id")).to eq(alice.user_id)
    end
  end
end
