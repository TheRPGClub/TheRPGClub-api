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

    it "returns a new suggestion as pending with empty review fields" do
      suggestion = create(:suggestion)

      get "/api/v1/suggestions", headers: auth_headers_for(create(:user))

      row = json.fetch("data").find { |s| s.fetch("suggestion_id") == suggestion.suggestion_id }
      expect(row).to include(
        "status" => "pending", "reviewed_by" => nil, "reviewed_at" => nil, "rejection_reason" => nil,
        "target_repo" => nil, "github_issue_number" => nil, "github_issue_url" => nil
      )
    end

    it "filters by one or more comma-separated statuses" do
      pending_one = create(:suggestion)
      approved = create(:suggestion, status: "approved")
      rejected = create(:suggestion, status: "rejected", rejection_reason: "No")
      withdrawn = create(:suggestion, status: "withdrawn")
      headers = auth_headers_for(create(:user))

      get "/api/v1/suggestions", params: { status: "pending,approved" }, headers: headers
      ids = json.fetch("data").map { |s| s.fetch("suggestion_id") }
      expect(ids).to contain_exactly(pending_one.suggestion_id, approved.suggestion_id)
      expect(json.dig("meta", "count")).to eq(2)

      get "/api/v1/suggestions", params: { status: "rejected" }, headers: headers
      expect(json.fetch("data").map { |s| s.fetch("suggestion_id") }).to eq([ rejected.suggestion_id ])

      get "/api/v1/suggestions", headers: headers
      expect(json.fetch("data").map { |s| s.fetch("suggestion_id") })
        .to include(pending_one.suggestion_id, withdrawn.suggestion_id)
    end

    it "400s for an unknown status" do
      get "/api/v1/suggestions", params: { status: "pending,bogus" }, headers: auth_headers_for(create(:user))

      expect(response).to have_http_status(:bad_request)
      expect(json.fetch("error")).to include("bogus")
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

    it "creates a suggestion for the bot" do
      expect {
        post "/api/v1/suggestions", params: payload, headers: service_headers, as: :json
      }.to change(RpgClubSuggestion, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(json.fetch("data")).to include(
        "title" => "Add dark mode",
        "details" => "Please",
        "created_by" => "77",
        "created_by_name" => "tester"
      )
    end

    it "lets any signed-in member create one as its author and asks the bot to ping the bot dev" do
      member = create(:user, username: "suggester")
      forged = { data: { title: "Dark mode", details: "Please", labels: "New Feature",
                         created_by: "999", created_by_name: "someone else" } }

      expect {
        post "/api/v1/suggestions", params: forged, headers: auth_headers_for(member), as: :json
      }.to change(RpgClubSuggestion, :count).by(1).and change(BotJob, :count).by(1)

      expect(response).to have_http_status(:created)
      data = json.fetch("data")
      expect(data).to include("title" => "Dark mode", "status" => "pending",
        "created_by" => member.user_id, "created_by_name" => "suggester")
      job = BotJob.last
      expect(job.kind).to eq("suggestion_submitted")
      expect(job.payload).to eq("suggestion_id" => data.fetch("suggestion_id"), "created_by" => member.user_id)
      expect(job.requested_by_user_id).to eq(member.user_id)
    end

    it "does not enqueue a ping for the bot's own submissions (the bot pings inline)" do
      expect {
        post "/api/v1/suggestions", params: payload, headers: service_headers, as: :json
      }.not_to change(BotJob, :count)
    end

    it "ignores status and review fields in the body" do
      body = { data: { title: "Sneaky", status: "approved", reviewed_by: "1", github_issue_number: 5 } }

      post "/api/v1/suggestions", params: body, headers: auth_headers_for(create(:user)), as: :json

      expect(response).to have_http_status(:created)
      expect(json.fetch("data")).to include("status" => "pending", "reviewed_by" => nil, "github_issue_number" => nil)
    end

    it "leaves no ping job when the create fails" do
      expect {
        post "/api/v1/suggestions", params: { data: { title: "" } }, headers: auth_headers_for(create(:user)), as: :json
      }.not_to change(BotJob, :count)

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "allows the service" do
      post "/api/v1/suggestions", params: payload, headers: service_headers, as: :json

      expect(response).to have_http_status(:created)
    end

    it "422s when title is missing" do
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

  describe "POST /api/v1/suggestions/:id/withdraw" do
    let(:author) { create(:user) }
    let(:suggestion) { create(:suggestion, created_by: author.user_id) }

    it "lets the author withdraw a pending suggestion" do
      post "/api/v1/suggestions/#{suggestion.suggestion_id}/withdraw", headers: auth_headers_for(author)

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("suggestion_id" => suggestion.suggestion_id, "status" => "withdrawn")
      get "/api/v1/suggestions/#{suggestion.suggestion_id}", headers: auth_headers_for(author)
      expect(json.dig("data", "status")).to eq("withdrawn")
    end

    it "refuses another member" do
      post "/api/v1/suggestions/#{suggestion.suggestion_id}/withdraw", headers: auth_headers_for(create(:user))

      expect(response).to have_http_status(:forbidden)
    end

    it "refuses staff who are not the author" do
      admin = create(:user, role_admin: true)

      post "/api/v1/suggestions/#{suggestion.suggestion_id}/withdraw", headers: auth_headers_for(admin, is_dev: true)

      expect(response).to have_http_status(:forbidden)
    end

    it "refuses the service, which has no author identity" do
      post "/api/v1/suggestions/#{suggestion.suggestion_id}/withdraw", headers: service_headers

      expect(response).to have_http_status(:forbidden)
    end

    %w[approved rejected withdrawn].each do |status|
      it "409s when the suggestion is #{status}" do
        suggestion.update!(status: status)

        post "/api/v1/suggestions/#{suggestion.suggestion_id}/withdraw", headers: auth_headers_for(author)

        expect(response).to have_http_status(:conflict)
        expect(json.fetch("error")).to include(status)
      end
    end

    it "404s for an unknown id" do
      post "/api/v1/suggestions/999999999/withdraw", headers: auth_headers_for(author)

      expect(response).to have_http_status(:not_found)
    end

    it "requires authentication" do
      post "/api/v1/suggestions/#{suggestion.suggestion_id}/withdraw"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "DELETE /api/v1/suggestions/:id" do
    it "deletes a suggestion for an admin" do
      suggestion = create(:suggestion)

      delete "/api/v1/suggestions/#{suggestion.suggestion_id}", headers: auth_headers_for(create(:user, role_admin: true))

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
