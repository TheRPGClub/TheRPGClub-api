# frozen_string_literal: true

require "rails_helper"

# Secret Santa after the draw (spec #376, "Secret Santa (Assignment)";
# ticket #384): a Santa sees only their recipient's backlog minus the games
# the recipient has Cleared and picks one before the pick deadline, and a
# Santa's identity is served to nobody but staff before the Edition ends.
# The timed side (the reminder, random picks, the reveal and the Edition's
# end) is in challenge_santa_lifecycle_spec.rb.
RSpec.describe "api/v1/challenge santa behavior", type: :request do
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

  # Secret Santa with the default calendar: its 2026 Edition opens on 26
  # December 2025, is drawn on 1 December 2026, takes picks until the start
  # of 15 December and is revealed on 25 December.
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

  # Signs `members` up and draws them on 1 December 2026 (after the block,
  # if given). With two members, each is the other's Santa.
  def draw(*members)
    members.each do |user|
      travel_to(club_time("2026-11-10 12:00")) do
        post "/api/v1/challenge_editions/#{edition_id}/signup", headers: auth_headers_for(user), as: :json
        expect(response).to have_http_status(:ok)
      end
    end
    yield if block_given?
    tick("2026-12-01 00:01")
  end

  def santa_view(as:, at: "2026-12-05 12:00", query: nil)
    travel_to(club_time(at)) do
      get "/api/v1/challenge_editions/#{edition_id}/santa", headers: auth_headers_for(as), params: { q: query }.compact
    end
  end

  def pick(game, as:, at: "2026-12-05 12:00")
    travel_to(club_time(at)) do
      put "/api/v1/challenge_editions/#{edition_id}/santa/pick", headers: auth_headers_for(as), as: :json,
        params: { data: { game_id: game.game_id } }
    end
  end

  describe "the Santa's view" do
    it "shows the Santa their recipient and the recipient's backlog minus the games they have Cleared" do
      draw(alice, bob)
      create(:completion, user: bob, game: backlog_game(bob, "Fallout"), completed_at: Time.utc(2019, 5, 1))

      santa_view(as: alice)

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("edition_id" => edition_id, "pick" => nil,
        "pick_deadline_on" => "2026-12-15", "picks_open" => true,
        "recipient" => include("user_id" => bob.user_id, "username" => bob.username))
      expect(json.dig("data", "backlog").map { |entry| entry.dig("game", "title") })
        .to contain_exactly("Arcanum", "Baldur's Gate", "Planescape", "Torment")
    end

    it "narrows the backlog by title" do
      draw(alice, bob)

      santa_view(as: alice, query: "plane")

      expect(json.dig("data", "backlog").map { |entry| entry.dig("game", "title") }).to eq([ "Planescape" ])
    end

    it "is refused to members who aren't a Santa, and before the draw" do
      carol = member_with_backlog("A", "B", "C", "D", "E")
      santa_view(as: alice, at: "2026-11-10 12:00")
      expect(response).to have_http_status(:forbidden)
      expect(json).to include("error" => "not_a_santa", "message" => "You aren't a Santa in the 2026 Edition.")

      draw(alice, bob)

      santa_view(as: carol)
      expect(response).to have_http_status(:forbidden)
      expect(json).to include("error" => "not_a_santa")
      expect(response.body).not_to include("Baldur")
    end

    it "shows the Santa the bot names" do
      draw(alice, bob)

      travel_to(club_time("2026-12-05 12:00")) do
        get "/api/v1/challenge_editions/#{edition_id}/santa", headers: service_headers,
          params: { acting_user_id: bob.user_id }
      end

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "recipient", "user_id")).to eq(alice.user_id)
    end
  end

  describe "picking" do
    it "records the Santa's pick, which they may change until the deadline" do
      draw(alice, bob)

      pick(backlog_game(bob, "Fallout"), as: alice, at: "2026-12-02 12:00")
      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "pick")).to include("picked_randomly" => false,
        "game" => include("title" => "Fallout"))

      pick(backlog_game(bob, "Torment"), as: alice, at: "2026-12-14 23:59")
      expect(response).to have_http_status(:ok)

      santa_view(as: alice, at: "2026-12-14 23:59")
      expect(json.dig("data", "pick", "game", "title")).to eq("Torment")
    end

    it "is refused from the start of the pick deadline day" do
      draw(alice, bob)

      pick(backlog_game(bob, "Fallout"), as: alice, at: "2026-12-15 00:00")

      expect(response).to have_http_status(:conflict)
      expect(json).to include("error" => "picks_closed",
        "message" => "Picks for the 2026 Edition closed on 15 December 2026.")
    end

    it "refuses a game the recipient has Cleared or that isn't in their backlog" do
      draw(alice, bob)
      create(:completion, user: bob, game: backlog_game(bob, "Fallout"), completed_at: Time.utc(2019, 5, 1))

      pick(backlog_game(bob, "Fallout"), as: alice)
      expect(response).to have_http_status(:unprocessable_content)
      expect(json).to include("error" => "not_eligible")

      pick(backlog_game(alice, "Okami"), as: alice)
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "is refused to members who aren't a Santa" do
      draw(alice, bob)

      pick(backlog_game(bob, "Fallout"), as: create(:user, role_member: true))

      expect(response).to have_http_status(:forbidden)
      expect(json).to include("error" => "not_a_santa")
    end

    it "records the pick of the Santa the bot names" do
      draw(alice, bob)

      travel_to(club_time("2026-12-05 12:00")) do
        put "/api/v1/challenge_editions/#{edition_id}/santa/pick", headers: service_headers, as: :json,
          params: { data: { acting_user_id: alice.user_id, game_id: backlog_game(bob, "Fallout").game_id } }
      end

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "pick", "game", "title")).to eq("Fallout")
    end
  end

  describe "withdrawing after the draw" do
    def withdraw(as:, at: "2026-12-05 12:00")
      travel_to(club_time(at)) do
        delete "/api/v1/challenge_editions/#{edition_id}/signup", headers: auth_headers_for(as)
      end
    end

    def runs_of(user)
      travel_to(club_time("2026-12-05 12:00")) do
        get "/api/v1/users/#{user.user_id}/challenge_runs", headers: auth_headers_for(user)
        json.fetch("data")
      end
    end

    it "drops the Santa's pick and Abandons their own Run, without redrawing the circle" do
      draw(alice, bob)
      pick(backlog_game(bob, "Fallout"), as: alice)

      withdraw(as: alice)

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "members")).to contain_exactly(
        include("user_id" => alice.user_id, "withdrawn" => true),
        include("user_id" => bob.user_id, "withdrawn" => false)
      )
      expect(runs_of(alice).sole).to include("status" => "abandoned")
      expect(runs_of(bob).sole).to include("status" => "active")

      santa_view(as: alice)
      expect(response).to have_http_status(:forbidden)
      santa_view(as: bob)
      expect(json.dig("data", "recipient", "user_id")).to eq(alice.user_id)
    end

    it "is refused from the pick deadline on, and to members the draw left out" do
      left_out = member_with_backlog("A", "B", "C", "D", "E")
      draw(alice, bob, left_out) do
        UserGameBacklog.where(user_id: left_out.user_id).first.destroy!
      end

      withdraw(as: alice, at: "2026-12-15 00:00")
      expect(response).to have_http_status(:conflict)
      expect(json).to include("error" => "picks_closed")

      withdraw(as: left_out)
      expect(response).to have_http_status(:conflict)
      expect(json).to include("error" => "not_drawn")
    end
  end
end
