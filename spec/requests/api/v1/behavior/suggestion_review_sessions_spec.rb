# frozen_string_literal: true

require "rails_helper"

# Behavior specs for the suggestion review-session endpoints (bot parity,
# #91): reads are open to any authenticated principal, writes are
# admin/service-gated, and pruning expired sessions is service-only.
RSpec.describe "api/v1/suggestions/review_sessions behavior", type: :request do
  describe "GET /api/v1/suggestions/review_sessions" do
    it "filters by reviewer_id and serializes the documented fields" do
      session = create(:suggestion_review_session, current_index: 1, total_count: 5)
      create(:suggestion_review_session)

      get "/api/v1/suggestions/review_sessions",
        params: { reviewer_id: session.reviewer_id }, headers: auth_headers_for(create(:user))

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data").length).to eq(1)
      expect(json.fetch("data").first).to include(
        "session_id" => session.session_id,
        "reviewer_id" => session.reviewer_id,
        "suggestion_ids" => "[1,2,3]",
        "current_index" => 1,
        "total_count" => 5
      )
      expect(json.fetch("meta")).to include("page" => 1, "count" => 1)
    end

    it "orders a reviewer's sessions newest first" do
      reviewer_id = SecureRandom.random_number(10**18).to_s
      older = create(:suggestion_review_session, reviewer_id: reviewer_id)
      newer = create(:suggestion_review_session, reviewer_id: reviewer_id)
      older.update_column(:created_at, 2.hours.ago)
      newer.update_column(:created_at, 1.hour.ago)

      get "/api/v1/suggestions/review_sessions", params: { reviewer_id: reviewer_id }, headers: service_headers

      ids = json.fetch("data").map { |s| s.fetch("session_id") }
      expect(ids).to eq([ newer.session_id, older.session_id ])
    end

    it "requires authentication" do
      get "/api/v1/suggestions/review_sessions"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/suggestions/review_sessions/:id" do
    it "shows a session by its session_id" do
      session = create(:suggestion_review_session)

      get "/api/v1/suggestions/review_sessions/#{session.session_id}", headers: auth_headers_for(create(:user))

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("session_id" => session.session_id)
    end

    it "404s for an unknown id" do
      get "/api/v1/suggestions/review_sessions/nope-#{SecureRandom.hex(4)}", headers: service_headers

      expect(response).to have_http_status(:not_found)
      expect(json).to have_key("error")
    end
  end

  describe "POST /api/v1/suggestions/review_sessions" do
    let(:payload) do
      { data: { session_id: "sess-#{SecureRandom.hex(8)}", reviewer_id: "9001",
                suggestion_ids: "[4,5]", current_index: 0, total_count: 2 } }
    end

    it "creates a session as the service" do
      expect {
        post "/api/v1/suggestions/review_sessions", params: payload, headers: service_headers, as: :json
      }.to change(RpgClubSuggestionReviewSession, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(json.fetch("data")).to include(
        "session_id" => payload.dig(:data, :session_id),
        "reviewer_id" => "9001",
        "suggestion_ids" => "[4,5]",
        "current_index" => 0,
        "total_count" => 2
      )
    end

    it "allows an admin user" do
      post "/api/v1/suggestions/review_sessions", params: payload,
        headers: auth_headers_for(create(:user, :admin)), as: :json

      expect(response).to have_http_status(:created)
    end

    it "forbids a regular user" do
      expect {
        post "/api/v1/suggestions/review_sessions", params: payload,
          headers: auth_headers_for(create(:user)), as: :json
      }.not_to change(RpgClubSuggestionReviewSession, :count)

      expect(response).to have_http_status(:forbidden)
      expect(json).to eq("error" => "forbidden")
    end

    it "422s for a duplicate session_id" do
      existing = create(:suggestion_review_session)
      payload[:data][:session_id] = existing.session_id

      post "/api/v1/suggestions/review_sessions", params: payload, headers: service_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("error")).to include("duplicate")
    end

    it "422s when reviewer_id is missing" do
      pending "possible bug: missing reviewer_id raises ActiveRecord::NotNullViolation and renders 500, " \
              "but the contract documents 422 (RpgClubSuggestionReviewSession has no presence validations)"

      post "/api/v1/suggestions/review_sessions",
        params: { data: { session_id: "sess-#{SecureRandom.hex(8)}", suggestion_ids: "[]" } },
        headers: service_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "400s when the data envelope is missing" do
      post "/api/v1/suggestions/review_sessions", params: {}, headers: service_headers, as: :json

      expect(response).to have_http_status(:bad_request)
    end

    it "requires authentication" do
      post "/api/v1/suggestions/review_sessions", params: payload, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "PATCH /api/v1/suggestions/review_sessions/:id" do
    it "advances the reviewer's progress as an admin" do
      session = create(:suggestion_review_session, current_index: 0)

      patch "/api/v1/suggestions/review_sessions/#{session.session_id}",
        params: { data: { current_index: 2 } }, headers: auth_headers_for(create(:user, :admin)), as: :json

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "current_index")).to eq(2)
      expect(session.reload.current_index).to eq(2)
    end

    it "forbids a regular user" do
      session = create(:suggestion_review_session, current_index: 0)

      patch "/api/v1/suggestions/review_sessions/#{session.session_id}",
        params: { data: { current_index: 9 } }, headers: auth_headers_for(create(:user)), as: :json

      expect(response).to have_http_status(:forbidden)
      expect(session.reload.current_index).to eq(0)
    end

    it "404s for an unknown id" do
      patch "/api/v1/suggestions/review_sessions/nope-#{SecureRandom.hex(4)}",
        params: { data: { current_index: 1 } }, headers: service_headers, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "DELETE /api/v1/suggestions/review_sessions/:id" do
    it "deletes a session as an admin" do
      session = create(:suggestion_review_session)

      delete "/api/v1/suggestions/review_sessions/#{session.session_id}",
        headers: auth_headers_for(create(:user, :admin))

      expect(response).to have_http_status(:ok)
      expect(json).to eq("deleted" => true)
      expect(RpgClubSuggestionReviewSession.exists?(session.session_id)).to be(false)
    end

    it "forbids a regular user" do
      session = create(:suggestion_review_session)

      delete "/api/v1/suggestions/review_sessions/#{session.session_id}", headers: auth_headers_for(create(:user))

      expect(response).to have_http_status(:forbidden)
      expect(RpgClubSuggestionReviewSession.exists?(session.session_id)).to be(true)
    end

    it "404s for an unknown id" do
      delete "/api/v1/suggestions/review_sessions/nope-#{SecureRandom.hex(4)}", headers: service_headers

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "DELETE /api/v1/suggestions/review_sessions (destroy_all)" do
    it "deletes every session for the reviewer as the service" do
      reviewer_id = SecureRandom.random_number(10**18).to_s
      create_list(:suggestion_review_session, 2, reviewer_id: reviewer_id)
      other = create(:suggestion_review_session)

      delete "/api/v1/suggestions/review_sessions", params: { reviewer_id: reviewer_id }, headers: service_headers

      expect(response).to have_http_status(:ok)
      expect(json).to eq("deleted" => true, "count" => 2)
      expect(RpgClubSuggestionReviewSession.where(reviewer_id: reviewer_id).count).to eq(0)
      expect(RpgClubSuggestionReviewSession.exists?(other.session_id)).to be(true)
    end

    it "400s without a reviewer_id" do
      delete "/api/v1/suggestions/review_sessions", headers: service_headers

      expect(response).to have_http_status(:bad_request)
      expect(json.fetch("error")).to include("reviewer_id")
    end

    it "forbids a regular user" do
      session = create(:suggestion_review_session)

      delete "/api/v1/suggestions/review_sessions",
        params: { reviewer_id: session.reviewer_id }, headers: auth_headers_for(create(:user))

      expect(response).to have_http_status(:forbidden)
      expect(RpgClubSuggestionReviewSession.exists?(session.session_id)).to be(true)
    end
  end

  describe "DELETE /api/v1/suggestions/review_sessions/expired" do
    it "prunes sessions older than the default 15-minute TTL as the service" do
      stale = create(:suggestion_review_session)
      stale.update_column(:created_at, 20.minutes.ago)
      fresh = create(:suggestion_review_session)

      delete "/api/v1/suggestions/review_sessions/expired", headers: service_headers

      expect(response).to have_http_status(:ok)
      expect(json).to include("deleted" => true)
      expect(RpgClubSuggestionReviewSession.exists?(stale.session_id)).to be(false)
      expect(RpgClubSuggestionReviewSession.exists?(fresh.session_id)).to be(true)
    end

    it "honours an explicit ISO-8601 before cutoff" do
      very_old = create(:suggestion_review_session)
      very_old.update_column(:created_at, 2.hours.ago)
      recent = create(:suggestion_review_session)
      recent.update_column(:created_at, 30.minutes.ago)

      delete "/api/v1/suggestions/review_sessions/expired",
        params: { before: 1.hour.ago.iso8601 }, headers: service_headers

      expect(response).to have_http_status(:ok)
      expect(RpgClubSuggestionReviewSession.exists?(very_old.session_id)).to be(false)
      expect(RpgClubSuggestionReviewSession.exists?(recent.session_id)).to be(true)
    end

    it "falls back to the TTL when before is unparseable" do
      stale = create(:suggestion_review_session)
      stale.update_column(:created_at, 20.minutes.ago)

      delete "/api/v1/suggestions/review_sessions/expired",
        params: { before: "not-a-date" }, headers: service_headers

      expect(response).to have_http_status(:ok)
      expect(RpgClubSuggestionReviewSession.exists?(stale.session_id)).to be(false)
    end

    it "forbids an admin user (service-only)" do
      stale = create(:suggestion_review_session)
      stale.update_column(:created_at, 20.minutes.ago)

      delete "/api/v1/suggestions/review_sessions/expired", headers: auth_headers_for(create(:user, :admin))

      expect(response).to have_http_status(:forbidden)
      expect(RpgClubSuggestionReviewSession.exists?(stale.session_id)).to be(true)
    end

    it "requires authentication" do
      delete "/api/v1/suggestions/review_sessions/expired"

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
