# frozen_string_literal: true

require "rails_helper"

# Behavior specs for the search-synonym draft endpoints: reads are open to any
# authenticated principal, writes are admin/dev/service-gated. Drafts carry an
# opaque pairs_json blob the bot round-trips verbatim.
RSpec.describe "api/v1/search_synonym_drafts behavior", type: :request do
  describe "GET /api/v1/search_synonym_drafts" do
    it "filters by user_id and serializes the documented fields" do
      draft = create(:search_synonym_draft)
      create(:search_synonym_draft)

      get "/api/v1/search_synonym_drafts", params: { user_id: draft.user_id }, headers: service_headers

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data").length).to eq(1)
      expect(json.fetch("data").first).to include(
        "draft_id" => draft.draft_id,
        "user_id" => draft.user_id,
        "pairs_json" => draft.pairs_json
      )
      expect(json.fetch("meta")).to include("page" => 1, "count" => 1)
    end

    it "orders a user's drafts by updated_at descending" do
      user_id = SecureRandom.random_number(10**18).to_s
      older = create(:search_synonym_draft, user_id: user_id)
      newer = create(:search_synonym_draft, user_id: user_id)
      older.update_column(:updated_at, 2.hours.ago)
      newer.update_column(:updated_at, 1.hour.ago)

      get "/api/v1/search_synonym_drafts", params: { user_id: user_id }, headers: auth_headers_for(create(:user))

      ids = json.fetch("data").map { |d| d.fetch("draft_id") }
      expect(ids).to eq([ newer.draft_id, older.draft_id ])
    end

    it "requires authentication" do
      get "/api/v1/search_synonym_drafts"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/search_synonym_drafts/:id" do
    it "shows a draft to any authenticated user" do
      draft = create(:search_synonym_draft)

      get "/api/v1/search_synonym_drafts/#{draft.draft_id}", headers: auth_headers_for(create(:user))

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("draft_id" => draft.draft_id, "user_id" => draft.user_id)
    end

    it "404s for an unknown id" do
      get "/api/v1/search_synonym_drafts/999999999", headers: service_headers

      expect(response).to have_http_status(:not_found)
      expect(json).to have_key("error")
    end
  end

  describe "POST /api/v1/search_synonym_drafts" do
    let(:payload) { { data: { user_id: "424242", pairs_json: '[{"from":"dq","to":"dragon quest"}]' } } }

    it "creates a draft as the service" do
      expect {
        post "/api/v1/search_synonym_drafts", params: payload, headers: service_headers, as: :json
      }.to change(GamedbSearchSynonymDraft, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(json.fetch("data")).to include(
        "user_id" => "424242",
        "pairs_json" => '[{"from":"dq","to":"dragon quest"}]'
      )
    end

    it "allows an admin user" do
      post "/api/v1/search_synonym_drafts", params: payload,
        headers: auth_headers_for(create(:user, :admin)), as: :json

      expect(response).to have_http_status(:created)
    end

    it "forbids a regular user" do
      expect {
        post "/api/v1/search_synonym_drafts", params: payload, headers: auth_headers_for(create(:user)), as: :json
      }.not_to change(GamedbSearchSynonymDraft, :count)

      expect(response).to have_http_status(:forbidden)
      expect(json).to eq("error" => "forbidden")
    end

    it "422s when user_id is missing" do
      post "/api/v1/search_synonym_drafts",
        params: { data: { pairs_json: "[]" } }, headers: service_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("error")).to include("User")
    end

    it "400s when the data envelope is missing" do
      post "/api/v1/search_synonym_drafts", params: {}, headers: service_headers, as: :json

      expect(response).to have_http_status(:bad_request)
    end

    it "requires authentication" do
      post "/api/v1/search_synonym_drafts", params: payload, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "PATCH /api/v1/search_synonym_drafts/:id" do
    it "updates the pairs blob as an admin" do
      draft = create(:search_synonym_draft)

      patch "/api/v1/search_synonym_drafts/#{draft.draft_id}",
        params: { data: { pairs_json: "[]" } }, headers: auth_headers_for(create(:user, :admin)), as: :json

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "pairs_json")).to eq("[]")
      expect(draft.reload.pairs_json).to eq("[]")
    end

    it "forbids a regular user" do
      draft = create(:search_synonym_draft)

      patch "/api/v1/search_synonym_drafts/#{draft.draft_id}",
        params: { data: { pairs_json: "hijacked" } }, headers: auth_headers_for(create(:user)), as: :json

      expect(response).to have_http_status(:forbidden)
      expect(draft.reload.pairs_json).not_to eq("hijacked")
    end

    it "404s for an unknown id" do
      patch "/api/v1/search_synonym_drafts/999999999",
        params: { data: { pairs_json: "[]" } }, headers: service_headers, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "DELETE /api/v1/search_synonym_drafts/:id" do
    it "deletes a draft as the service" do
      draft = create(:search_synonym_draft)

      delete "/api/v1/search_synonym_drafts/#{draft.draft_id}", headers: service_headers

      expect(response).to have_http_status(:ok)
      expect(json).to eq("deleted" => true)
      expect(GamedbSearchSynonymDraft.exists?(draft.draft_id)).to be(false)
    end

    it "forbids a regular user" do
      draft = create(:search_synonym_draft)

      delete "/api/v1/search_synonym_drafts/#{draft.draft_id}", headers: auth_headers_for(create(:user))

      expect(response).to have_http_status(:forbidden)
      expect(GamedbSearchSynonymDraft.exists?(draft.draft_id)).to be(true)
    end
  end
end
