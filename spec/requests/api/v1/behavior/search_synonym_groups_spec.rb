# frozen_string_literal: true

require "rails_helper"

# Behavior specs for the search-synonym group endpoints (#108): reads are open
# to any authenticated principal, writes (including the bulk terms delete) are
# admin/dev/service-gated. Deleting a group cascades to its terms.
RSpec.describe "api/v1/search_synonym_groups behavior", type: :request do
  describe "GET /api/v1/search_synonym_groups" do
    it "lists groups with the documented fields" do
      group = create(:search_synonym_group)
      create(:search_synonym, group: group, term_text: "GrpFind zk1")

      get "/api/v1/search_synonym_groups", params: { q: "grpfind zk1" }, headers: service_headers

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data").length).to eq(1)
      expect(json.fetch("data").first).to include(
        "group_id" => group.group_id,
        "created_by" => group.created_by
      )
      expect(json.fetch("meta")).to include("page" => 1, "count" => 1)
    end

    it "matches ?q= through the group's terms by normalised substring" do
      group = create(:search_synonym_group)
      create(:search_synonym, group: group, term_text: "Grand-Find zk2")
      other = create(:search_synonym_group)
      create(:search_synonym, group: other, term_text: "Suikoden zk3")

      get "/api/v1/search_synonym_groups", params: { q: "grandfind" }, headers: auth_headers_for(create(:user))

      ids = json.fetch("data").map { |g| g.fetch("group_id") }
      expect(ids).to eq([ group.group_id ])
    end

    it "requires authentication" do
      get "/api/v1/search_synonym_groups"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/search_synonym_groups/:id" do
    it "shows a group to any authenticated user" do
      group = create(:search_synonym_group)

      get "/api/v1/search_synonym_groups/#{group.group_id}", headers: auth_headers_for(create(:user))

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("group_id" => group.group_id, "created_by" => group.created_by)
    end

    it "404s for an unknown id" do
      get "/api/v1/search_synonym_groups/999999999", headers: service_headers

      expect(response).to have_http_status(:not_found)
      expect(json).to have_key("error")
    end
  end

  describe "POST /api/v1/search_synonym_groups" do
    let(:payload) { { data: { created_by: "1234" } } }

    it "creates a group as an admin" do
      expect {
        post "/api/v1/search_synonym_groups", params: payload,
          headers: auth_headers_for(create(:user, :admin)), as: :json
      }.to change(GamedbSearchSynonymGroup, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(json.fetch("data")).to include("created_by" => "1234")
      expect(json.dig("data", "group_id")).to be_a(Integer)
    end

    it "allows the service" do
      post "/api/v1/search_synonym_groups", params: payload, headers: service_headers, as: :json

      expect(response).to have_http_status(:created)
    end

    it "forbids a regular user" do
      expect {
        post "/api/v1/search_synonym_groups", params: payload, headers: auth_headers_for(create(:user)), as: :json
      }.not_to change(GamedbSearchSynonymGroup, :count)

      expect(response).to have_http_status(:forbidden)
      expect(json).to eq("error" => "forbidden")
    end

    it "400s when the data envelope is missing" do
      post "/api/v1/search_synonym_groups", params: {}, headers: service_headers, as: :json

      expect(response).to have_http_status(:bad_request)
    end

    it "requires authentication" do
      post "/api/v1/search_synonym_groups", params: payload, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "PATCH /api/v1/search_synonym_groups/:id" do
    it "updates a group as the service" do
      group = create(:search_synonym_group)

      patch "/api/v1/search_synonym_groups/#{group.group_id}",
        params: { data: { created_by: "5678" } }, headers: service_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "created_by")).to eq("5678")
      expect(group.reload.created_by).to eq("5678")
    end

    it "forbids a regular user" do
      group = create(:search_synonym_group)

      patch "/api/v1/search_synonym_groups/#{group.group_id}",
        params: { data: { created_by: "hijacked" } }, headers: auth_headers_for(create(:user)), as: :json

      expect(response).to have_http_status(:forbidden)
      expect(group.reload.created_by).not_to eq("hijacked")
    end

    it "404s for an unknown id" do
      patch "/api/v1/search_synonym_groups/999999999",
        params: { data: { created_by: "x" } }, headers: service_headers, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "DELETE /api/v1/search_synonym_groups/:id" do
    it "deletes the group and cascades to its terms" do
      group = create(:search_synonym_group)
      synonym = create(:search_synonym, group: group)

      delete "/api/v1/search_synonym_groups/#{group.group_id}", headers: service_headers

      expect(response).to have_http_status(:ok)
      expect(json).to eq("deleted" => true)
      expect(GamedbSearchSynonymGroup.exists?(group.group_id)).to be(false)
      expect(GamedbSearchSynonym.exists?(synonym.term_id)).to be(false)
    end

    it "forbids a regular user" do
      group = create(:search_synonym_group)

      delete "/api/v1/search_synonym_groups/#{group.group_id}", headers: auth_headers_for(create(:user))

      expect(response).to have_http_status(:forbidden)
      expect(GamedbSearchSynonymGroup.exists?(group.group_id)).to be(true)
    end

    it "404s for an unknown id" do
      delete "/api/v1/search_synonym_groups/999999999", headers: auth_headers_for(create(:user, :admin))

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "DELETE /api/v1/search_synonym_groups/:id/terms" do
    it "bulk-deletes the group's terms but keeps the group" do
      group = create(:search_synonym_group)
      create_list(:search_synonym, 2, group: group)
      untouched = create(:search_synonym)

      delete "/api/v1/search_synonym_groups/#{group.group_id}/terms",
        headers: auth_headers_for(create(:user, :admin))

      expect(response).to have_http_status(:ok)
      expect(json).to eq("deleted" => true, "count" => 2)
      expect(GamedbSearchSynonymGroup.exists?(group.group_id)).to be(true)
      expect(group.synonyms.count).to eq(0)
      expect(GamedbSearchSynonym.exists?(untouched.term_id)).to be(true)
    end

    it "forbids a regular user" do
      group = create(:search_synonym_group)
      create(:search_synonym, group: group)

      delete "/api/v1/search_synonym_groups/#{group.group_id}/terms", headers: auth_headers_for(create(:user))

      expect(response).to have_http_status(:forbidden)
      expect(group.synonyms.count).to eq(1)
    end

    it "404s for an unknown group" do
      delete "/api/v1/search_synonym_groups/999999999/terms", headers: service_headers

      expect(response).to have_http_status(:not_found)
    end
  end
end
