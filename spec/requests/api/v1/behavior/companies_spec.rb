# frozen_string_literal: true

require "rails_helper"

# Behavior specs for the companies taxonomy endpoints (TaxonomyEndpoints
# concern): list/search/pagination and show. Companies have no IGDB-id upsert
# column, so the table is read-only (no create route).
RSpec.describe "api/v1/companies behavior", type: :request do
  describe "GET /api/v1/companies" do
    it "lists companies ordered by name with pagination meta" do
      create(:company, name: "ordtest zz softworks")
      create(:company, name: "ordtest aa interactive")

      get "/api/v1/companies", params: { q: "ordtest" }, headers: service_headers

      expect(response).to have_http_status(:ok)
      names = json.fetch("data").map { |c| c.fetch("name") }
      expect(names).to eq([ "ordtest aa interactive", "ordtest zz softworks" ])
      expect(json.fetch("meta")).to include("page" => 1, "count" => 2)
    end

    it "serializes the documented company fields" do
      company = create(:company)

      get "/api/v1/companies", params: { q: company.name }, headers: service_headers

      expect(json.fetch("data").first).to include(
        "company_id" => company.company_id,
        "name" => company.name,
        "igdb_company_id" => company.igdb_company_id
      )
    end

    it "filters by q case-insensitively" do
      match = create(:company, name: "Square Enix xq1")
      create(:company, name: "Capcom xq2")

      get "/api/v1/companies", params: { q: "square enix" }, headers: service_headers

      names = json.fetch("data").map { |c| c.fetch("name") }
      expect(names).to include(match.name)
      expect(names).not_to include("Capcom xq2")
    end

    it "paginates with page/per" do
      create_list(:company, 3)

      get "/api/v1/companies", params: { per: 2, page: 1 }, headers: service_headers

      expect(json.fetch("data").length).to eq(2)
      expect(json.fetch("meta")).to include("per" => 2, "page" => 1)
      expect(json.dig("meta", "pages")).to be >= 2
    end

    it "supports the legacy limit/offset alias" do
      create_list(:company, 3)

      get "/api/v1/companies", params: { limit: 2, offset: 2 }, headers: service_headers

      expect(json.fetch("data").length).to be <= 2
      expect(json.fetch("meta")).to include("per" => 2, "page" => 2)
    end

    it "is readable by a regular user" do
      company = create(:company)

      get "/api/v1/companies", params: { q: company.name }, headers: auth_headers_for(create(:user))

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data").first).to include("company_id" => company.company_id)
    end

    it "requires authentication" do
      get "/api/v1/companies"

      expect(response).to have_http_status(:unauthorized)
      expect(json).to eq("error" => "unauthorized")
    end
  end

  describe "GET /api/v1/companies/:id" do
    it "returns the company" do
      company = create(:company)

      get "/api/v1/companies/#{company.company_id}", headers: service_headers

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("company_id" => company.company_id, "name" => company.name)
    end

    it "404s for an unknown id" do
      get "/api/v1/companies/999999999", headers: service_headers

      expect(response).to have_http_status(:not_found)
      expect(json).to have_key("error")
    end

    it "requires authentication" do
      company = create(:company)

      get "/api/v1/companies/#{company.company_id}"

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
