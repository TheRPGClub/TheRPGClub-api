# frozen_string_literal: true

require "rails_helper"

# Behavior specs for the flat search-synonym term endpoints (#108): reads are
# open to any authenticated principal, writes are admin/dev/service-gated.
RSpec.describe "api/v1/search_synonyms behavior", type: :request do
  describe "GET /api/v1/search_synonyms" do
    it "lists a group's terms with the documented fields" do
      group = create(:search_synonym_group)
      synonym = create(:search_synonym, group: group, term_text: "FF7")
      create(:search_synonym)

      get "/api/v1/search_synonyms", params: { group_id: group.group_id }, headers: service_headers

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data").length).to eq(1)
      expect(json.fetch("data").first).to include(
        "term_id" => synonym.term_id,
        "group_id" => group.group_id,
        "term_text" => "FF7",
        "term_norm" => "ff7",
        "created_by" => synonym.created_by
      )
      expect(json.fetch("meta")).to include("page" => 1, "count" => 1)
    end

    it "matches ?term= against the normalised key" do
      match = create(:search_synonym, term_text: "FF7 Probe")
      create(:search_synonym, term_text: "Chrono Probe")

      get "/api/v1/search_synonyms", params: { term: "ff-7 PROBE!" }, headers: auth_headers_for(create(:user))

      ids = json.fetch("data").map { |t| t.fetch("term_id") }
      expect(ids).to eq([ match.term_id ])
    end

    it "matches ?q= by literal text case-insensitively and by normalised substring" do
      literal = create(:search_synonym, term_text: "Chrono Trigger xq1")
      normalised = create(:search_synonym, term_text: "Chro-No Trig xq2")
      create(:search_synonym, term_text: "Suikoden xq3")

      get "/api/v1/search_synonyms", params: { q: "chronotrig" }, headers: service_headers

      ids = json.fetch("data").map { |t| t.fetch("term_id") }
      expect(ids).to contain_exactly(literal.term_id, normalised.term_id)
    end

    it "requires authentication" do
      get "/api/v1/search_synonyms"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/search_synonyms/:id" do
    it "shows a term to any authenticated user" do
      synonym = create(:search_synonym)

      get "/api/v1/search_synonyms/#{synonym.term_id}", headers: auth_headers_for(create(:user))

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include(
        "term_id" => synonym.term_id,
        "term_text" => synonym.term_text,
        "term_norm" => synonym.term_norm
      )
    end

    it "404s for an unknown id" do
      get "/api/v1/search_synonyms/999999999", headers: service_headers

      expect(response).to have_http_status(:not_found)
      expect(json).to have_key("error")
    end
  end

  describe "POST /api/v1/search_synonyms" do
    let(:group) { create(:search_synonym_group) }
    let(:payload) do
      { data: { group_id: group.group_id, term_text: "FFVII", term_norm: "ffvii", created_by: "42" } }
    end

    it "creates a term as the service" do
      expect {
        post "/api/v1/search_synonyms", params: payload, headers: service_headers, as: :json
      }.to change(GamedbSearchSynonym, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(json.fetch("data")).to include(
        "group_id" => group.group_id, "term_text" => "FFVII", "term_norm" => "ffvii", "created_by" => "42"
      )
    end

    it "allows an admin user" do
      post "/api/v1/search_synonyms", params: payload, headers: auth_headers_for(create(:user, :admin)), as: :json

      expect(response).to have_http_status(:created)
    end

    it "allows a dev session" do
      post "/api/v1/search_synonyms", params: payload,
        headers: auth_headers_for(create(:user), is_dev: true), as: :json

      expect(response).to have_http_status(:created)
    end

    it "forbids a regular user" do
      expect {
        post "/api/v1/search_synonyms", params: payload, headers: auth_headers_for(create(:user)), as: :json
      }.not_to change(GamedbSearchSynonym, :count)

      expect(response).to have_http_status(:forbidden)
      expect(json).to eq("error" => "forbidden")
    end

    it "422s when term_text is missing" do
      post "/api/v1/search_synonyms",
        params: { data: { group_id: group.group_id, term_norm: "x" } }, headers: service_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "422s for an unknown group_id" do
      post "/api/v1/search_synonyms",
        params: { data: { group_id: 999_999_999, term_text: "x", term_norm: "x" } },
        headers: service_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "400s when the data envelope is missing" do
      post "/api/v1/search_synonyms", params: { term_text: "bare" }, headers: service_headers, as: :json

      expect(response).to have_http_status(:bad_request)
    end

    it "requires authentication" do
      post "/api/v1/search_synonyms", params: payload, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "PATCH /api/v1/search_synonyms/:id" do
    it "updates a term as an admin" do
      synonym = create(:search_synonym)

      patch "/api/v1/search_synonyms/#{synonym.term_id}",
        params: { data: { term_text: "Renamed", term_norm: "renamed" } },
        headers: auth_headers_for(create(:user, :admin)), as: :json

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("term_text" => "Renamed", "term_norm" => "renamed")
      expect(synonym.reload.term_text).to eq("Renamed")
    end

    it "forbids a regular user" do
      synonym = create(:search_synonym)

      patch "/api/v1/search_synonyms/#{synonym.term_id}",
        params: { data: { term_text: "hijacked" } }, headers: auth_headers_for(create(:user)), as: :json

      expect(response).to have_http_status(:forbidden)
      expect(synonym.reload.term_text).not_to eq("hijacked")
    end

    it "422s when term_text is blanked" do
      synonym = create(:search_synonym)

      patch "/api/v1/search_synonyms/#{synonym.term_id}",
        params: { data: { term_text: "" } }, headers: service_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "404s for an unknown id" do
      patch "/api/v1/search_synonyms/999999999",
        params: { data: { term_text: "x" } }, headers: service_headers, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "DELETE /api/v1/search_synonyms/:id" do
    it "deletes a term as the service" do
      synonym = create(:search_synonym)

      delete "/api/v1/search_synonyms/#{synonym.term_id}", headers: service_headers

      expect(response).to have_http_status(:ok)
      expect(json).to eq("deleted" => true)
      expect(GamedbSearchSynonym.exists?(synonym.term_id)).to be(false)
    end

    it "forbids a regular user" do
      synonym = create(:search_synonym)

      delete "/api/v1/search_synonyms/#{synonym.term_id}", headers: auth_headers_for(create(:user))

      expect(response).to have_http_status(:forbidden)
      expect(GamedbSearchSynonym.exists?(synonym.term_id)).to be(true)
    end
  end
end
