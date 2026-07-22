# frozen_string_literal: true

require "rails_helper"

# Behavior specs for the presence prompt history endpoints (#48/#110): reads
# are open to any authenticated caller, creation and resolution are
# service-only (the bot's presence-detection loop owns every write).
RSpec.describe "api/v1/presence_prompts behavior", type: :request do
  let(:owner) { create(:user) }

  describe "GET /api/v1/users/:user_id/presence_prompts" do
    it "lists only that user's prompts, newest first" do
      older = create(:presence_prompt, user_id: owner.user_id, created_at: 2.days.ago)
      newer = create(:presence_prompt, user_id: owner.user_id, created_at: 1.day.ago)
      create(:presence_prompt)

      get "/api/v1/users/#{owner.user_id}/presence_prompts", headers: auth_headers_for(create(:user))

      expect(response).to have_http_status(:ok)
      ids = json.fetch("data").map { |p| p.fetch("prompt_id") }
      expect(ids).to eq([ newer.prompt_id, older.prompt_id ])
      expect(json.fetch("data").first).to include(
        "prompt_id" => newer.prompt_id,
        "user_id" => owner.user_id,
        "game_title" => newer.game_title,
        "game_title_norm" => newer.game_title_norm,
        "status" => "PENDING",
        "resolved_at" => nil
      )
    end

    it "filters by game_title_norm with the count in meta" do
      match = create(:presence_prompt, user_id: owner.user_id, game_title: "Chrono Trigger",
        game_title_norm: "chronotrigger")
      create(:presence_prompt, user_id: owner.user_id)

      get "/api/v1/users/#{owner.user_id}/presence_prompts",
        params: { game_title_norm: "chronotrigger" }, headers: service_headers

      expect(json.fetch("data").map { |p| p.fetch("prompt_id") }).to eq([ match.prompt_id ])
      expect(json.dig("meta", "count")).to eq(1)
    end

    it "filters by status case-insensitively" do
      pending_prompt = create(:presence_prompt, user_id: owner.user_id)
      create(:presence_prompt, user_id: owner.user_id, status: "ACCEPTED")

      get "/api/v1/users/#{owner.user_id}/presence_prompts",
        params: { status: "pending" }, headers: service_headers

      expect(json.fetch("data").map { |p| p.fetch("prompt_id") }).to eq([ pending_prompt.prompt_id ])
      expect(json.dig("meta", "count")).to eq(1)
    end

    it "requires authentication" do
      get "/api/v1/users/#{owner.user_id}/presence_prompts"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "POST /api/v1/users/:user_id/presence_prompts" do
    let(:prompt_id) { SecureRandom.random_number(10**18).to_s }
    let(:payload) do
      { data: { prompt_id: prompt_id, game_title: "Chrono Trigger", game_title_norm: "chronotrigger" } }
    end

    it "creates a PENDING prompt for the user as the service" do
      expect {
        post "/api/v1/users/#{owner.user_id}/presence_prompts",
          params: payload, headers: service_headers, as: :json
      }.to change(PresencePrompt.where(user_id: owner.user_id), :count).by(1)

      expect(response).to have_http_status(:created)
      expect(json.fetch("data")).to include(
        "prompt_id" => prompt_id,
        "user_id" => owner.user_id,
        "game_title" => "Chrono Trigger",
        "game_title_norm" => "chronotrigger",
        "status" => "PENDING",
        "resolved_at" => nil
      )
      expect(json.dig("data", "created_at")).to be_present
    end

    it "ignores client-sent status, resolved_at and created_at" do
      post "/api/v1/users/#{owner.user_id}/presence_prompts",
        params: { data: payload[:data].merge(status: "ACCEPTED", resolved_at: "2000-01-01T00:00:00Z",
          created_at: "2000-01-01T00:00:00Z") },
        headers: service_headers, as: :json

      expect(response).to have_http_status(:created)
      record = PresencePrompt.find(prompt_id)
      expect(record.status).to eq("PENDING")
      expect(record.resolved_at).to be_nil
      expect(record.created_at).to be > 1.day.ago
    end

    it "takes the user id from the path, not the body" do
      post "/api/v1/users/#{owner.user_id}/presence_prompts",
        params: { data: payload[:data].merge(user_id: "999999999") }, headers: service_headers, as: :json

      expect(response).to have_http_status(:created)
      expect(PresencePrompt.find(prompt_id).user_id).to eq(owner.user_id)
    end

    it "422s when game_title is missing" do
      post "/api/v1/users/#{owner.user_id}/presence_prompts",
        params: { data: { prompt_id: prompt_id, game_title_norm: "x" } }, headers: service_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "422s on a duplicate prompt_id" do
      create(:presence_prompt, prompt_id: prompt_id)

      post "/api/v1/users/#{owner.user_id}/presence_prompts",
        params: payload, headers: service_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("error")).to include("duplicate")
    end

    it "400s when the data envelope is missing" do
      post "/api/v1/users/#{owner.user_id}/presence_prompts",
        params: { prompt_id: prompt_id }, headers: service_headers, as: :json

      expect(response).to have_http_status(:bad_request)
    end

    it "forbids a regular user, even the owner" do
      expect {
        post "/api/v1/users/#{owner.user_id}/presence_prompts",
          params: payload, headers: auth_headers_for(owner), as: :json
      }.not_to change(PresencePrompt, :count)

      expect(response).to have_http_status(:forbidden)
    end

    it "forbids an admin (service-only)" do
      post "/api/v1/users/#{owner.user_id}/presence_prompts",
        params: payload, headers: auth_headers_for(create(:user, :admin)), as: :json

      expect(response).to have_http_status(:forbidden)
    end

    it "requires authentication" do
      post "/api/v1/users/#{owner.user_id}/presence_prompts", params: payload, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "PATCH /api/v1/presence_prompts/:id" do
    let(:prompt) { create(:presence_prompt, user_id: owner.user_id) }

    it "resolves the prompt as the service" do
      patch "/api/v1/presence_prompts/#{prompt.prompt_id}",
        params: { data: { status: "ACCEPTED", resolved_at: "2026-07-20T12:00:00Z" } },
        headers: service_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("prompt_id" => prompt.prompt_id, "status" => "ACCEPTED")
      expect(json.dig("data", "resolved_at")).to be_present
      expect(prompt.reload.status).to eq("ACCEPTED")
      expect(prompt.resolved_at).to eq(Time.zone.parse("2026-07-20T12:00:00Z"))
    end

    it "supports PUT as an alias" do
      put "/api/v1/presence_prompts/#{prompt.prompt_id}",
        params: { data: { status: "DECLINED" } }, headers: service_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(prompt.reload.status).to eq("DECLINED")
    end

    it "ignores the immutable identity and game-title fields" do
      patch "/api/v1/presence_prompts/#{prompt.prompt_id}",
        params: { data: { status: "DECLINED", game_title: "hijacked", game_title_norm: "hijacked",
          user_id: "999999999" } },
        headers: service_headers, as: :json

      expect(response).to have_http_status(:ok)
      reloaded = prompt.reload
      expect(reloaded.status).to eq("DECLINED")
      expect(reloaded.game_title).to eq(prompt.game_title)
      expect(reloaded.user_id).to eq(owner.user_id)
    end

    it "422s for an invalid status" do
      patch "/api/v1/presence_prompts/#{prompt.prompt_id}",
        params: { data: { status: "NOT_A_STATUS" } }, headers: service_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(prompt.reload.status).to eq("PENDING")
    end

    it "404s for an unknown prompt" do
      patch "/api/v1/presence_prompts/unknown-prompt-id",
        params: { data: { status: "ACCEPTED" } }, headers: service_headers, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it "400s when the data envelope is missing" do
      patch "/api/v1/presence_prompts/#{prompt.prompt_id}",
        params: { status: "ACCEPTED" }, headers: service_headers, as: :json

      expect(response).to have_http_status(:bad_request)
    end

    it "forbids a regular user" do
      patch "/api/v1/presence_prompts/#{prompt.prompt_id}",
        params: { data: { status: "ACCEPTED" } }, headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:forbidden)
      expect(prompt.reload.status).to eq("PENDING")
    end

    it "requires authentication" do
      patch "/api/v1/presence_prompts/#{prompt.prompt_id}",
        params: { data: { status: "ACCEPTED" } }, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
