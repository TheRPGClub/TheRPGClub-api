# frozen_string_literal: true

require "rails_helper"

# Game of the Year nominations over HTTP (spec api#471, ticket api#473). The
# nomination rules themselves (cap, eligibility, window) are specified in
# spec/services/goty/nominate_spec.rb; these cover who may do what, the
# error codes and the ballot.
RSpec.describe "api/v1/goty_votes nominations behavior", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:member) { create(:user) }
  let(:admin) { create(:user, role_admin: true) }
  let!(:vote) { create(:goty_vote, year: 2026) }
  let(:nominating_at) { Time.utc(2027, 1, 5) }
  let(:path) { "/api/v1/goty_votes/2026/nominations" }

  def game_from(year)
    create(:game, initial_release_date: Time.utc(year, 6, 1))
  end

  def post_nomination(game, as: member, reason: nil, user_id: nil, at: nominating_at)
    body = { data: { gamedb_game_id: game.game_id, reason: reason, user_id: user_id }.compact }
    travel_to(at) { post path, params: body, headers: headers_for(as), as: :json }
  end

  def delete_nomination(nomination, as:, at: nominating_at)
    travel_to(at) { delete "#{path}/#{nomination.id}", headers: headers_for(as) }
  end

  # Called inside travel_to, so the session token is fresh at that time.
  def headers_for(principal)
    principal == :service ? service_headers : auth_headers_for(principal)
  end

  describe "POST /goty_votes/:year/nominations" do
    it "nominates for the signed-in member, and updates the reason on a second post" do
      game = game_from(2026)

      post_nomination(game, reason: "Loved it")

      expect(response).to have_http_status(:created)
      data = json.fetch("data")
      expect(data).to include("year" => 2026, "user_id" => member.user_id, "gamedb_game_id" => game.game_id,
        "reason" => "Loved it")
      expect(data.dig("user", "user_id")).to eq(member.user_id)
      expect(data.dig("game", "title")).to eq(game.title)

      post_nomination(game, reason: "Still love it")

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "id")).to eq(data["id"])
      expect(json.dig("data", "reason")).to eq("Still love it")
    end

    it "refuses a fourth nomination" do
      3.times { post_nomination(game_from(2026)) }

      post_nomination(game_from(2026))

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["error"]).to eq("nomination_cap_reached")
    end

    it "refuses an ineligible game with the reason as the error code" do
      post_nomination(game_from(2025))
      expect(response).to have_http_status(:unprocessable_content)
      expect(json["error"]).to eq("not_released_in_year")

      post_nomination(create(:game))
      expect(response).to have_http_status(:unprocessable_content)
      expect(json["error"]).to eq("release_unknown")
      expect(json["message"]).to match(/ask staff to record its release/)
    end

    it "is closed once voting opens" do
      post_nomination(game_from(2026), at: vote.voting_opens_at + 1.minute)

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["error"]).to eq("nominations_closed")
    end

    it "refuses a reason over 1500 characters" do
      post_nomination(game_from(2026), reason: "x" * 1501)

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "lets a member nominate only for themselves" do
      post_nomination(game_from(2026), user_id: create(:user).user_id)

      expect(response).to have_http_status(:forbidden)
    end

    it "lets the service nominate for a named member" do
      post_nomination(game_from(2026), as: :service, user_id: member.user_id)

      expect(response).to have_http_status(:created)
      expect(json.dig("data", "user_id")).to eq(member.user_id)
    end

    it "needs a user_id from the service" do
      post_nomination(game_from(2026), as: :service)

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["error"]).to eq("user_id_required")
    end

    it "is not found for an unknown game or year" do
      travel_to(nominating_at) do
        post path, params: { data: { gamedb_game_id: 0 } }, headers: auth_headers_for(member), as: :json
      end
      expect(response).to have_http_status(:not_found)

      travel_to(nominating_at) do
        post "/api/v1/goty_votes/1999/nominations", params: { data: { gamedb_game_id: game_from(1999).game_id } },
          headers: auth_headers_for(member), as: :json
      end
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /goty_votes/:year/nominations" do
    it "lists every nomination with its nominator and reason, oldest first, and filters by member" do
      first = create(:goty_nomination, year: 2026, user: member, reason: "First", nominated_at: Time.utc(2027, 1, 2))
      second = create(:goty_nomination, year: 2026, reason: "Second", nominated_at: Time.utc(2027, 1, 3))

      get path, headers: auth_headers_for(member)

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data").map { |row| row.values_at("id", "reason") }).to eq([
        [ first.id, "First" ], [ second.id, "Second" ]
      ])
      expect(json.dig("data", 0, "user", "username")).to eq(member.username)

      get path, params: { user_id: member.user_id }, headers: auth_headers_for(member)

      expect(json.fetch("data").map { |row| row["id"] }).to eq([ first.id ])
    end

    it "is not found for a year with no GOTY Vote" do
      get "/api/v1/goty_votes/1999/nominations", headers: auth_headers_for(member)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "DELETE /goty_votes/:year/nominations/:id" do
    let(:nomination) { create(:goty_nomination, year: 2026, user: member) }

    it "lets the owner withdraw while nominating" do
      delete_nomination(nomination, as: member)

      expect(response).to have_http_status(:ok)
      expect(json).to eq("deleted" => true)
      expect(GotyNomination.exists?(nomination.id)).to be(false)
    end

    it "keeps another member's nomination" do
      delete_nomination(nomination, as: create(:user))

      expect(response).to have_http_status(:forbidden)
      expect(GotyNomination.exists?(nomination.id)).to be(true)
    end

    it "is closed to the owner and admins once voting opens" do
      delete_nomination(nomination, as: member, at: vote.voting_opens_at)
      expect(response).to have_http_status(:unprocessable_content)
      expect(json["error"]).to eq("nominations_closed")

      delete_nomination(nomination, as: admin, at: vote.voting_opens_at)
      expect(response).to have_http_status(:unprocessable_content)
      expect(GotyNomination.exists?(nomination.id)).to be(true)
    end

    it "lets an admin remove any nomination before voting opens" do
      delete_nomination(nomination, as: admin)

      expect(response).to have_http_status(:ok)
      expect(GotyNomination.exists?(nomination.id)).to be(false)
    end

    it "lets the service remove a nomination before voting opens" do
      delete_nomination(nomination, as: :service)

      expect(response).to have_http_status(:ok)
    end

    it "is not found for a nomination from another year" do
      create(:goty_vote, year: 2025)
      other = create(:goty_nomination, year: 2025, user: member)

      delete_nomination(other, as: member)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /goty_votes/:year" do
    it "shows a game two members nominated once on the Game of the Year ballot" do
      shared, solo = create_list(:game, 2)
      create(:goty_nomination, year: 2026, game: shared, nominated_at: Time.utc(2027, 1, 2))
      create(:goty_nomination, year: 2026, game: shared, nominated_at: Time.utc(2027, 1, 3))
      create(:goty_nomination, year: 2026, game: solo, nominated_at: Time.utc(2027, 1, 4))

      travel_to(nominating_at) { get "/api/v1/goty_votes/2026", headers: auth_headers_for(member) }

      award = json.dig("data", "awards").find { |row| row["award"] == "game_of_the_year" }
      expect(award["ballot"].map { |game| game["game_id"] }).to eq([ shared.game_id, solo.game_id ])
    end
  end
end
