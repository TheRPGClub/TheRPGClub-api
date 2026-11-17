# frozen_string_literal: true

require "rails_helper"

# Secret Santa (spec #376, "Secret Santa (Assignment)"; ticket #383): an
# Assignment Challenge's calendar, its Editions, and signing up for one and
# withdrawing before the sign-up cutoff. The draw and the Edition's timed
# side are in challenge_edition_lifecycle_spec.rb.
RSpec.describe "api/v1/challenge editions behavior", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:moderator) { create(:user, role_member: true, role_moderator: true) }
  let(:member) { create(:user, role_member: true) }

  def club_time(text) = ActiveSupport::TimeZone[Challenges::TIME_ZONE].parse(text)

  def create_santa(as: moderator, **overrides)
    post "/api/v1/challenges", headers: auth_headers_for(as), as: :json, params: { data: {
      name: "Secret Santa", description: "Pick a game from another member's backlog.",
      challenge_format: "assignment", schedule: "always_open", hosted_by_club: true
    }.merge(overrides) }
  end

  describe "creating an Assignment Challenge" do
    it "defaults to the Secret Santa calendar and opens its first Edition's sign-up straight away" do
      travel_to(club_time("2026-11-02 12:00")) { create_santa }

      expect(response).to have_http_status(:created)
      expect(json.fetch("data")).to include("challenge_format" => "assignment", "open" => true, "pool" => nil)
      expect(json.dig("data", "assignment")).to include(
        "signup_cutoff" => "12-01", "pick_deadline" => "12-15", "reveal" => "12-25"
      )
      expect(json.dig("data", "assignment", "edition")).to include("year" => 2026, "phase" => "signup",
        "signup_opens_on" => "2026-11-02", "signup_cutoff_on" => "2026-12-01", "pick_deadline_on" => "2026-12-15",
        "reveal_on" => "2026-12-25", "ends_on" => "2027-12-25")
    end

    it "takes a calendar of its own, as months and days" do
      travel_to(club_time("2026-03-01 12:00")) do
        create_santa(assignment: { signup_cutoff: "06-01", pick_deadline: "06-20", reveal: "07-04" })
      end

      expect(response).to have_http_status(:created)
      expect(json.dig("data", "assignment")).to include("signup_cutoff" => "06-01", "pick_deadline" => "06-20",
        "reveal" => "07-04")
      expect(json.dig("data", "assignment", "edition")).to include("year" => 2026,
        "signup_opens_on" => "2026-03-01", "signup_cutoff_on" => "2026-06-01", "reveal_on" => "2026-07-04",
        "ends_on" => "2027-07-04")
    end

    it "takes a calendar crossing the new year, the reveal naming the Edition" do
      travel_to(club_time("2026-11-02 12:00")) do
        create_santa(assignment: { signup_cutoff: "12-20", pick_deadline: "01-05", reveal: "01-15" })
      end

      expect(json.dig("data", "assignment", "edition")).to include("year" => 2027,
        "signup_opens_on" => "2026-11-02", "signup_cutoff_on" => "2026-12-20", "pick_deadline_on" => "2027-01-05",
        "reveal_on" => "2027-01-15")
    end

    it "waits for the next Edition when this year's cutoff has passed: it opens the day after the reveal" do
      travel_to(club_time("2026-12-10 12:00")) { create_santa }

      expect(response).to have_http_status(:created)
      expect(json.dig("data", "assignment", "edition")).to be_nil
    end

    it "refuses a calendar out of order, a repeated day, 29 February, a Season and an end date" do
      travel_to(club_time("2026-11-02 12:00")) do
        create_santa(assignment: { signup_cutoff: "12-20", pick_deadline: "12-15", reveal: "12-25" })
        expect(response).to have_http_status(:unprocessable_content)
        expect(json.fetch("message")).to include("must come in that order through the year")

        create_santa(assignment: { signup_cutoff: "12-15", pick_deadline: "12-15", reveal: "12-25" })
        expect(json.fetch("message")).to include("must be different days")

        create_santa(assignment: { reveal: "02-29" })
        expect(json.fetch("message")).to include("must be a day every year has")

        create_santa(schedule: "seasonal", season: { start: "12-01", end: "12-31" })
        expect(response).to have_http_status(:unprocessable_content)
        expect(json.fetch("message")).to include("so it is Always Open")

        create_santa(ends_on: "2027-12-31")
        expect(json.fetch("message")).to include("so it has no end date")
      end
    end
  end

  describe "changing the calendar" do
    it "moves the Edition in sign-up to the new dates while nobody has joined it" do
      challenge_id = travel_to(club_time("2026-11-02 12:00")) do
        create_santa
        json.dig("data", "id")
      end

      travel_to(club_time("2026-11-03 12:00")) do
        patch "/api/v1/challenges/#{challenge_id}", params: { data: { assignment: { signup_cutoff: "12-05" } } },
          headers: auth_headers_for(moderator), as: :json
      end

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "assignment")).to include("signup_cutoff" => "12-05", "pick_deadline" => "12-15")
      expect(json.dig("data", "assignment", "edition")).to include("signup_opens_on" => "2026-11-02",
        "signup_cutoff_on" => "2026-12-05")
    end

    it "has the lifecycle job look again on the next minute, since its next step moved" do
      challenge_id = travel_to(club_time("2026-11-02 12:00")) do
        create_santa
        json.dig("data", "id")
      end
      Challenges::SweepSchedule.record(club_time("2026-11-28 00:00"), club_time("2026-11-03 12:00"))

      travel_to(club_time("2026-11-03 12:00")) do
        patch "/api/v1/challenges/#{challenge_id}", params: { data: { assignment: { signup_cutoff: "11-20" } } },
          headers: auth_headers_for(moderator), as: :json
      end

      expect(Challenges::SweepSchedule.due?(club_time("2026-11-03 12:01"))).to be(true)
    ensure
      Challenges::SweepSchedule.clear
    end
  end

  # Secret Santa, created on 2 November 2026: the 2026 Edition's sign-up is
  # open until its cutoff, the start of 1 December.
  let!(:santa) do
    travel_to(club_time("2026-11-02 12:00")) { create_santa }
    Challenge.find(json.dig("data", "id"))
  end
  let(:edition_id) { santa.editions.sole.id }

  def with_backlog(user, games)
    create_list(:backlog_entry, games, user: user)
    user
  end

  def sign_up(as:, at: "2026-11-10 12:00")
    travel_to(club_time(at)) do
      post "/api/v1/challenge_editions/#{edition_id}/signup", headers: auth_headers_for(as), as: :json
    end
  end

  def withdraw(as:, at: "2026-11-10 12:00")
    travel_to(club_time(at)) do
      delete "/api/v1/challenge_editions/#{edition_id}/signup", headers: auth_headers_for(as), as: :json
    end
  end

  describe "signing up" do
    it "signs up a member with 5 games in their backlog, who then shows on the Edition" do
      with_backlog(member, 5)

      sign_up(as: member)

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("year" => 2026, "phase" => "signup", "signup_open" => true,
        "signed_up" => true, "signed_up_count" => 1)
      expect(json.dig("data", "members")).to contain_exactly(
        include("user_id" => member.user_id, "username" => member.username, "left_out" => false)
      )
    end

    it "refuses a member with fewer than 5 games in their backlog, and says why" do
      with_backlog(member, 3)

      sign_up(as: member)

      expect(response).to have_http_status(:unprocessable_content)
      expect(json).to include("error" => "backlog_too_small", "minimum" => 5, "backlog_count" => 3,
        "message" => "You need at least 5 games in your backlog to sign up, so your Santa has a real choice. " \
                     "You have 3.")
    end

    it "refuses a second sign-up" do
      with_backlog(member, 5)
      sign_up(as: member)

      sign_up(as: member)

      expect(response).to have_http_status(:conflict)
      expect(json).to include("error" => "already_signed_up")
    end

    it "is open until the day before the cutoff, and refused from the cutoff on" do
      with_backlog(member, 5)

      sign_up(as: member, at: "2026-11-30 23:59")
      expect(response).to have_http_status(:ok)

      sign_up(as: with_backlog(create(:user, role_member: true), 5), at: "2026-12-01 00:00")
      expect(response).to have_http_status(:conflict)
      expect(json).to include("error" => "signup_closed",
        "message" => "Sign-up for the 2026 Edition closed on 1 December 2026.")
    end

    it "signs up the member the bot names" do
      with_backlog(member, 5)

      travel_to(club_time("2026-11-10 12:00")) do
        post "/api/v1/challenge_editions/#{edition_id}/signup", headers: service_headers, as: :json,
          params: { data: { acting_user_id: member.user_id } }
      end

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "signed_up")).to be(true)
    end
  end

  describe "withdrawing" do
    it "takes the member off the Edition before the cutoff" do
      with_backlog(member, 5)
      sign_up(as: member)

      withdraw(as: member, at: "2026-11-30 12:00")

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("signed_up" => false, "signed_up_count" => 0, "members" => [])
    end

    it "is refused from the cutoff on, and for a member who isn't signed up" do
      with_backlog(member, 5)
      sign_up(as: member)

      withdraw(as: member, at: "2026-12-01 00:01")
      expect(response).to have_http_status(:conflict)
      expect(json).to include("error" => "signup_closed")

      withdraw(as: create(:user, role_member: true))
      expect(response).to have_http_status(:conflict)
      expect(json).to include("error" => "not_signed_up")
    end

    it "takes the member the bot names off the Edition" do
      with_backlog(member, 5)
      sign_up(as: member)

      travel_to(club_time("2026-11-10 12:00")) do
        delete "/api/v1/challenge_editions/#{edition_id}/signup?acting_user_id=#{member.user_id}",
          headers: service_headers
      end

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "signed_up_count")).to eq(0)
    end
  end

  describe "reading Editions" do
    it "shows an Edition and lists the Challenge's Editions, newest first" do
      with_backlog(member, 5)
      sign_up(as: member)

      travel_to(club_time("2026-11-10 12:00")) do
        get "/api/v1/challenge_editions/#{edition_id}", headers: auth_headers_for(moderator)
        expect(response).to have_http_status(:ok)
        expect(json.fetch("data")).to include("id" => edition_id, "year" => 2026, "signed_up" => false,
          "signed_up_count" => 1, "challenge" => { "id" => santa.id, "name" => "Secret Santa" })

        get "/api/v1/challenges/#{santa.id}/editions", headers: auth_headers_for(member)
        expect(json.fetch("data").map { |edition| edition["id"] }).to eq([ edition_id ])
        expect(json.dig("data", 0, "signed_up")).to be(true)
      end
    end

    it "lists a member's sign-ups that have no Run yet with their Runs, under meta.signups" do
      with_backlog(member, 5)
      sign_up(as: member)
      signed_up_at = ChallengeEditionSignup.find_by!(user_id: member.user_id).signed_up_at

      travel_to(club_time("2026-11-10 12:00")) do
        get "/api/v1/users/#{member.user_id}/challenge_runs", headers: auth_headers_for(member)
      end

      expect(json.fetch("data")).to eq([])
      expect(json.dig("meta", "signups")).to eq([ {
        "edition_id" => edition_id, "year" => 2026, "phase" => "signup",
        "challenge" => { "id" => santa.id, "name" => "Secret Santa" },
        "signed_up_at" => signed_up_at.as_json, "signup_cutoff_on" => "2026-12-01",
        "pick_deadline_on" => "2026-12-15", "reveal_on" => "2026-12-25"
      } ])

      travel_to(club_time("2026-11-10 12:00")) do
        get "/api/v1/users/#{moderator.user_id}/challenge_runs", headers: auth_headers_for(member)
      end
      expect(json.dig("meta", "signups")).to eq([])
    end

    it "leaves sign-ups out once the draw gave them a Run, and a hidden Challenge's out for others" do
      with_backlog(member, 5)
      sign_up(as: member)
      santa.update!(hidden: true)

      travel_to(club_time("2026-11-10 12:00")) do
        get "/api/v1/users/#{member.user_id}/challenge_runs", headers: auth_headers_for(moderator)
        expect(json.dig("meta", "signups").size).to eq(1)

        get "/api/v1/users/#{member.user_id}/challenge_runs", headers: auth_headers_for(member)
        expect(json.dig("meta", "signups").size).to eq(1)

        get "/api/v1/users/#{member.user_id}/challenge_runs", headers: auth_headers_for(create(:user, role_member: true))
        expect(json.dig("meta", "signups")).to eq([])
      end

      santa.update!(hidden: false)
      santa.editions.sole.update!(phase: "picking")
      create(:challenge_run, challenge: santa, user: member, edition: santa.editions.sole)

      travel_to(club_time("2026-12-02 12:00")) do
        get "/api/v1/users/#{member.user_id}/challenge_runs", headers: auth_headers_for(member)
      end
      expect(json.dig("meta", "signups")).to eq([])
    end

    it "hides a hidden Challenge's Editions from members" do
      santa.update!(hidden: true)

      get "/api/v1/challenge_editions/#{edition_id}", headers: auth_headers_for(member)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "starting a Run" do
    it "is refused: Secret Santa Runs come from the draw" do
      travel_to(club_time("2026-11-10 12:00")) do
        post "/api/v1/challenges/#{santa.id}/runs", headers: auth_headers_for(member), as: :json
      end

      expect(response).to have_http_status(:conflict)
      expect(json).to include("error" => "signup_required")
    end
  end
end
