# frozen_string_literal: true

require "rails_helper"

# Behavior specs for the read-only per-user nickname-change log (bot parity,
# #49): the bot owns every write, the API only lists.
RSpec.describe "api/v1/user_nick_history behavior", type: :request do
  let(:owner) { create(:user) }

  describe "GET /api/v1/users/:user_id/nick_history" do
    it "lists only that user's events newest first with all columns" do
      older = create(:nick_history_event, user: owner, changed_at: 2.days.ago)
      newer = create(:nick_history_event, user: owner, changed_at: 1.day.ago)
      create(:nick_history_event) # another user's event

      get "/api/v1/users/#{owner.user_id}/nick_history", headers: auth_headers_for(create(:user))

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data").map { |e| e.fetch("event_id") }).to eq([ newer.event_id, older.event_id ])
      expect(json.fetch("data").first).to include(
        "event_id" => newer.event_id,
        "user_id" => owner.user_id,
        "old_nick" => newer.old_nick,
        "new_nick" => newer.new_nick
      )
      expect(json.fetch("data").first).to have_key("changed_at")
      expect(json.fetch("meta")).to include("page" => 1, "count" => 2)
    end

    it "breaks changed_at ties by event_id descending" do
      at = 1.hour.ago
      first = create(:nick_history_event, user: owner, changed_at: at)
      second = create(:nick_history_event, user: owner, changed_at: at)

      get "/api/v1/users/#{owner.user_id}/nick_history", headers: service_headers

      expect(json.fetch("data").map { |e| e.fetch("event_id") }).to eq([ second.event_id, first.event_id ])
    end

    it "paginates with page/per" do
      create_list(:nick_history_event, 3, user: owner)

      get "/api/v1/users/#{owner.user_id}/nick_history",
        params: { per: 2, page: 2 }, headers: service_headers

      expect(json.fetch("data").length).to eq(1)
      expect(json.fetch("meta")).to include("per" => 2, "page" => 2, "count" => 3, "pages" => 2)
    end

    it "returns an empty list for a user with no history" do
      get "/api/v1/users/#{owner.user_id}/nick_history", headers: service_headers

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to eq([])
      expect(json.fetch("meta")).to include("count" => 0)
    end

    it "requires authentication" do
      get "/api/v1/users/#{owner.user_id}/nick_history"

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
