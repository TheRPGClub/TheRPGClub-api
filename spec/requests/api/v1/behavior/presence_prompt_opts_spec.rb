# frozen_string_literal: true

require "rails_helper"

# Behavior specs for the presence-prompt opt-out preference document (#48):
# GET is open to any authenticated caller; PUT replaces the whole set and is
# owner-only (the service may write on the user's behalf).
RSpec.describe "api/v1/presence_prompt_opts behavior", type: :request do
  let(:owner) { create(:user) }

  describe "GET /api/v1/users/:user_id/presence_prompt_opts" do
    it "returns the opt-out document with the ALL flag and per-game entries" do
      create(:presence_prompt_opt, :all, user_id: owner.user_id)
      create(:presence_prompt_opt, user_id: owner.user_id, game_title: "Final Fantasy VII",
        game_title_norm: "finalfantasyvii")
      create(:presence_prompt_opt)

      get "/api/v1/users/#{owner.user_id}/presence_prompt_opts", headers: auth_headers_for(create(:user))

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("user_id" => owner.user_id, "all" => true)
      games = json.dig("data", "games")
      expect(games.length).to eq(1)
      expect(games.first).to include(
        "game_title" => "Final Fantasy VII",
        "game_title_norm" => "finalfantasyvii"
      )
    end

    it "returns an empty preference for a user with no opt-outs" do
      get "/api/v1/users/#{owner.user_id}/presence_prompt_opts", headers: service_headers

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("user_id" => owner.user_id, "all" => false, "games" => [])
    end

    it "requires authentication" do
      get "/api/v1/users/#{owner.user_id}/presence_prompt_opts"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "PUT /api/v1/users/:user_id/presence_prompt_opts" do
    it "replaces the opt-out set, normalizing and deduplicating titles" do
      create(:presence_prompt_opt, user_id: owner.user_id, game_title: "Old Game", game_title_norm: "oldgame")

      put "/api/v1/users/#{owner.user_id}/presence_prompt_opts",
        params: { data: { all: true, games: [ "Final Fantasy VII", "final fantasy vii!!", "", "Chrono Trigger" ] } },
        headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "all")).to be(true)
      norms = json.dig("data", "games").map { |g| g.fetch("game_title_norm") }
      expect(norms).to eq([ "chronotrigger", "finalfantasyvii" ])

      rows = PresencePromptOpt.where(user_id: owner.user_id)
      expect(rows.count).to eq(3)
      expect(rows.where(game_title_norm: "oldgame")).to be_empty
      expect(rows.where(scope: PresencePromptOpt::SCOPE_ALL).count).to eq(1)
    end

    it "clears the opt-outs when given an empty set (opt back in)" do
      create(:presence_prompt_opt, :all, user_id: owner.user_id)
      create(:presence_prompt_opt, user_id: owner.user_id)

      put "/api/v1/users/#{owner.user_id}/presence_prompt_opts",
        params: { data: { all: false, games: [] } }, headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("all" => false, "games" => [])
      expect(PresencePromptOpt.where(user_id: owner.user_id)).to be_empty
    end

    it "allows the service to write on the user's behalf" do
      put "/api/v1/users/#{owner.user_id}/presence_prompt_opts",
        params: { data: { games: [ "Suikoden II" ] } }, headers: service_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(PresencePromptOpt.where(user_id: owner.user_id, game_title_norm: "suikodenii")).to exist
    end

    it "forbids another user" do
      existing = create(:presence_prompt_opt, user_id: owner.user_id)

      put "/api/v1/users/#{owner.user_id}/presence_prompt_opts",
        params: { data: { all: true } }, headers: auth_headers_for(create(:user)), as: :json

      expect(response).to have_http_status(:forbidden)
      rows = PresencePromptOpt.where(user_id: owner.user_id)
      expect(rows.count).to eq(1)
      expect(rows.first.game_title_norm).to eq(existing.game_title_norm)
    end

    it "400s when the data envelope is missing" do
      put "/api/v1/users/#{owner.user_id}/presence_prompt_opts",
        params: { all: true }, headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:bad_request)
    end

    it "requires authentication" do
      put "/api/v1/users/#{owner.user_id}/presence_prompt_opts",
        params: { data: { all: true } }, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
