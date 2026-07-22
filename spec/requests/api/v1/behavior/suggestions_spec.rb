# frozen_string_literal: true

require "rails_helper"

# Behavior specs for the suggestion-box endpoints: every action (including
# create and destroy) is open to any authenticated principal.
RSpec.describe "api/v1/suggestions behavior", type: :request do
  describe "GET /api/v1/suggestions" do
    it "lists suggestions newest first with the documented fields" do
      older = create(:suggestion, labels: "bug,ux")
      newer = create(:suggestion)
      older.update_column(:created_at, 2.hours.ago)
      newer.update_column(:created_at, 1.hour.ago)

      get "/api/v1/suggestions", params: { per: 500 }, headers: auth_headers_for(create(:user))

      expect(response).to have_http_status(:ok)
      ids = json.fetch("data").map { |s| s.fetch("suggestion_id") }
      expect(ids.index(newer.suggestion_id)).to be < ids.index(older.suggestion_id)
      row = json.fetch("data").find { |s| s.fetch("suggestion_id") == older.suggestion_id }
      expect(row).to include(
        "title" => older.title,
        "details" => older.details,
        "labels" => "bug,ux",
        "created_by" => older.created_by,
        "created_by_name" => older.created_by_name
      )
      expect(json.fetch("meta")).to include("page" => 1)
    end

    it "requires authentication" do
      get "/api/v1/suggestions"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/suggestions/:id" do
    it "shows a suggestion" do
      suggestion = create(:suggestion)

      get "/api/v1/suggestions/#{suggestion.suggestion_id}", headers: auth_headers_for(create(:user))

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include(
        "suggestion_id" => suggestion.suggestion_id,
        "title" => suggestion.title
      )
    end

    it "404s for an unknown id" do
      get "/api/v1/suggestions/999999999", headers: service_headers

      expect(response).to have_http_status(:not_found)
      expect(json).to have_key("error")
    end
  end

  describe "POST /api/v1/suggestions" do
    let(:payload) do
      { data: { title: "Add dark mode", details: "Please", created_by: "77", created_by_name: "tester" } }
    end

    it "creates a suggestion for a regular user" do
      expect {
        post "/api/v1/suggestions", params: payload, headers: auth_headers_for(create(:user)), as: :json
      }.to change(RpgClubSuggestion, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(json.fetch("data")).to include(
        "title" => "Add dark mode",
        "details" => "Please",
        "created_by" => "77",
        "created_by_name" => "tester"
      )
    end

    it "allows the service" do
      post "/api/v1/suggestions", params: payload, headers: service_headers, as: :json

      expect(response).to have_http_status(:created)
    end

    it "422s when title is missing" do
      pending "possible bug: missing title raises ActiveRecord::NotNullViolation and renders 500, " \
              "but the contract documents 422 (RpgClubSuggestion has no presence validation)"

      post "/api/v1/suggestions", params: { data: { details: "no title" } }, headers: service_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "422s when title exceeds the column limit" do
      post "/api/v1/suggestions", params: { data: { title: "x" * 201 } }, headers: service_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "400s when the data envelope is missing" do
      post "/api/v1/suggestions", params: { title: "bare" }, headers: service_headers, as: :json

      expect(response).to have_http_status(:bad_request)
    end

    it "requires authentication" do
      post "/api/v1/suggestions", params: payload, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "DELETE /api/v1/suggestions/:id" do
    it "deletes a suggestion for any authenticated user" do
      suggestion = create(:suggestion)

      delete "/api/v1/suggestions/#{suggestion.suggestion_id}", headers: auth_headers_for(create(:user))

      expect(response).to have_http_status(:ok)
      expect(json).to eq("deleted" => true)
      expect(RpgClubSuggestion.exists?(suggestion.suggestion_id)).to be(false)
    end

    it "404s for an unknown id" do
      delete "/api/v1/suggestions/999999999", headers: service_headers

      expect(response).to have_http_status(:not_found)
    end
  end
end
