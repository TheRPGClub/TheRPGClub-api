# frozen_string_literal: true

require "rails_helper"

# Behavior specs for the completion endpoints: reads are open to any
# authenticated principal, writes are gated to the owner (or the service).
RSpec.describe "api/v1/completions behavior", type: :request do
  let(:owner) { create(:user) }
  let(:other_user) { create(:user) }

  describe "GET /api/v1/users/:user_id/completions" do
    it "lists only that user's completions with the embedded game and platform" do
      platform = create(:platform)
      completion = create(:completion, user: owner, platform: platform, note: "beat it")
      create(:completion, user: other_user)

      get "/api/v1/users/#{owner.user_id}/completions", headers: auth_headers_for(other_user)

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data").length).to eq(1)
      expect(json.fetch("data").first).to include(
        "completion_id" => completion.completion_id,
        "user_id" => owner.user_id,
        "gamedb_game_id" => completion.gamedb_game_id,
        "completion_type" => "Main Story",
        "platform_id" => platform.platform_id,
        "note" => "beat it"
      )
      expect(json.dig("data", 0, "game")).to include("game_id" => completion.gamedb_game_id)
      expect(json.dig("data", 0, "platform")).to include("platform_id" => platform.platform_id)
    end

    it "filters by game_id with an exact meta.count" do
      keeper = create(:completion, user: owner)
      create(:completion, user: owner)

      get "/api/v1/users/#{owner.user_id}/completions",
        params: { game_id: keeper.gamedb_game_id }, headers: service_headers

      expect(json.fetch("data").map { |c| c.fetch("completion_id") }).to eq([ keeper.completion_id ])
      expect(json.dig("meta", "count")).to eq(1)
    end

    it "filters by year, with the literal unknown matching null completed_at" do
      completed_2020 = create(:completion, user: owner, completed_at: Time.utc(2020, 5, 5))
      unknown = create(:completion, user: owner)
      unknown.update_columns(completed_at: nil)

      get "/api/v1/users/#{owner.user_id}/completions", params: { year: "2020" }, headers: service_headers
      expect(json.fetch("data").map { |c| c.fetch("completion_id") }).to eq([ completed_2020.completion_id ])

      get "/api/v1/users/#{owner.user_id}/completions", params: { year: "unknown" }, headers: service_headers
      expect(json.fetch("data").map { |c| c.fetch("completion_id") }).to eq([ unknown.completion_id ])
    end

    it "filters by q on the game title, case-insensitively" do
      game = create(:game, title: "cmplq secret quest #{SecureRandom.hex(4)}")
      match = create(:completion, user: owner, game: game)
      create(:completion, user: owner)

      get "/api/v1/users/#{owner.user_id}/completions", params: { q: "CMPLQ SECRET" }, headers: service_headers

      expect(json.fetch("data").map { |c| c.fetch("completion_id") }).to eq([ match.completion_id ])
    end

    it "requires authentication" do
      get "/api/v1/users/#{owner.user_id}/completions"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/games/:id/completions" do
    it "lists a game's completions with the completing user embedded" do
      game = create(:game)
      entry = create(:completion, user: owner, game: game)
      create(:completion, user: owner)

      get "/api/v1/games/#{game.game_id}/completions", headers: auth_headers_for(other_user)

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data").map { |c| c.fetch("completion_id") }).to eq([ entry.completion_id ])
      expect(json.dig("data", 0, "user")).to include("user_id" => owner.user_id)
    end
  end

  describe "GET /api/v1/completions/leaderboard" do
    it "ranks active members by matching completion count, excluding departed members" do
      prefix = "ldbq #{SecureRandom.hex(4)}"
      top = create(:user)
      runner_up = create(:user)
      departed = create(:user, server_left_at: Time.current)
      3.times { create(:completion, user: top, game: create(:game, title: "#{prefix} #{SecureRandom.hex(4)}")) }
      create(:completion, user: runner_up, game: create(:game, title: "#{prefix} #{SecureRandom.hex(4)}"))
      create(:completion, user: departed, game: create(:game, title: "#{prefix} #{SecureRandom.hex(4)}"))

      get "/api/v1/completions/leaderboard", params: { q: prefix }, headers: auth_headers_for(other_user)

      expect(response).to have_http_status(:ok)
      rows = json.fetch("data")
      expect(rows.map { |r| r.fetch("user_id") }).to eq([ top.user_id, runner_up.user_id ])
      expect(rows.first).to include("username" => top.username, "completion_count" => 3)
      expect(json.dig("meta", "count")).to eq(2)
    end

    it "requires authentication" do
      get "/api/v1/completions/leaderboard"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "POST /api/v1/users/:user_id/completions" do
    let(:game) { create(:game) }
    let(:payload) { { data: { gamedb_game_id: game.game_id, completion_type: "Main Story", note: "done" } } }

    it "creates a completion for the owner" do
      expect {
        post "/api/v1/users/#{owner.user_id}/completions",
          params: payload, headers: auth_headers_for(owner), as: :json
      }.to change(UserGameCompletion.where(user_id: owner.user_id), :count).by(1)

      expect(response).to have_http_status(:created)
      expect(json.fetch("data")).to include(
        "user_id" => owner.user_id,
        "gamedb_game_id" => game.game_id,
        "completion_type" => "Main Story",
        "note" => "done"
      )
      expect(json.dig("data", "game", "game_id")).to eq(game.game_id)
    end

    it "allows the service to write on behalf of a user" do
      post "/api/v1/users/#{owner.user_id}/completions", params: payload, headers: service_headers, as: :json

      expect(response).to have_http_status(:created)
    end

    it "forbids another user" do
      expect {
        post "/api/v1/users/#{owner.user_id}/completions",
          params: payload, headers: auth_headers_for(other_user), as: :json
      }.not_to change(UserGameCompletion, :count)

      expect(response).to have_http_status(:forbidden)
    end

    it "422s for an unknown game id" do
      post "/api/v1/users/#{owner.user_id}/completions",
        params: { data: { gamedb_game_id: 999_999_999, completion_type: "Main Story" } },
        headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "422s when completion_type is missing" do
      post "/api/v1/users/#{owner.user_id}/completions",
        params: { data: { gamedb_game_id: game.game_id } }, headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "400s when the data envelope is missing" do
      post "/api/v1/users/#{owner.user_id}/completions",
        params: { gamedb_game_id: game.game_id }, headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:bad_request)
    end

    it "requires authentication" do
      post "/api/v1/users/#{owner.user_id}/completions", params: payload, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/completions/:id" do
    it "shows a completion to any authenticated user" do
      completion = create(:completion, user: owner)

      get "/api/v1/completions/#{completion.completion_id}", headers: auth_headers_for(other_user)

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("completion_id" => completion.completion_id)
    end

    it "404s for an unknown id" do
      get "/api/v1/completions/999999999", headers: service_headers

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "PATCH /api/v1/completions/:id" do
    it "updates the owner's completion" do
      completion = create(:completion, user: owner)

      patch "/api/v1/completions/#{completion.completion_id}",
        params: { data: { note: "updated note" } }, headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "note")).to eq("updated note")
      expect(completion.reload.note).to eq("updated note")
    end

    it "allows the service" do
      completion = create(:completion, user: owner)

      patch "/api/v1/completions/#{completion.completion_id}",
        params: { data: { note: "service note" } }, headers: service_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(completion.reload.note).to eq("service note")
    end

    it "forbids a non-owner" do
      completion = create(:completion, user: owner)

      patch "/api/v1/completions/#{completion.completion_id}",
        params: { data: { note: "hijacked" } }, headers: auth_headers_for(other_user), as: :json

      expect(response).to have_http_status(:forbidden)
      expect(completion.reload.note).not_to eq("hijacked")
    end

    it "404s for an unknown id (as the service)" do
      patch "/api/v1/completions/999999999",
        params: { data: { note: "x" } }, headers: service_headers, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it "422s when completion_type is blanked" do
      completion = create(:completion, user: owner)

      patch "/api/v1/completions/#{completion.completion_id}",
        params: { data: { completion_type: "" } }, headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "DELETE /api/v1/completions/:id" do
    it "deletes the owner's completion" do
      completion = create(:completion, user: owner)

      delete "/api/v1/completions/#{completion.completion_id}", headers: auth_headers_for(owner)

      expect(response).to have_http_status(:ok)
      expect(json).to eq("deleted" => true)
      expect(UserGameCompletion.exists?(completion.completion_id)).to be(false)
    end

    it "forbids a non-owner" do
      completion = create(:completion, user: owner)

      delete "/api/v1/completions/#{completion.completion_id}", headers: auth_headers_for(other_user)

      expect(response).to have_http_status(:forbidden)
      expect(UserGameCompletion.exists?(completion.completion_id)).to be(true)
    end
  end
end
