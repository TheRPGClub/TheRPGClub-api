# frozen_string_literal: true

require "rails_helper"

# Behavior specs for the bot's outbox: service-only claim (a lease) and ack.
RSpec.describe "api/v1/voting_events behavior", type: :request do
  let(:round_number) { SecureRandom.random_number(1_000_000_000) }

  def event(**attrs)
    VotingEvent.create!({ round_number: round_number, kind: "voting_opened", available_at: 1.minute.ago }.merge(attrs))
  end

  describe "POST /api/v1/voting_events/claim" do
    it "leases due events to the service" do
      due = event(payload: { "voting_closes_at" => "2026-11-02T04:59:59Z" })

      post "/api/v1/voting_events/claim", headers: service_headers

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data").sole).to include(
        "id" => due.id, "kind" => "voting_opened", "round_number" => round_number, "attempts" => 1,
        "payload" => { "voting_closes_at" => "2026-11-02T04:59:59Z" }
      )

      post "/api/v1/voting_events/claim", headers: service_headers
      expect(json.fetch("data")).to be_empty
    end

    it "honors ?limit" do
      event
      event(kind: "voting_closed")

      post "/api/v1/voting_events/claim?limit=1", headers: service_headers

      expect(json.fetch("data").size).to eq(1)
    end

    it "is forbidden to admins and members" do
      post "/api/v1/voting_events/claim", headers: auth_headers_for(create(:user, role_admin: true))

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "POST /api/v1/voting_events/:id/ack" do
    it "marks the event delivered" do
      pending_event = event

      post "/api/v1/voting_events/#{pending_event.id}/ack", headers: service_headers

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "delivered_at")).to be_present
      expect(pending_event.reload.delivered_at).to be_present
    end

    it "404s for an unknown event" do
      post "/api/v1/voting_events/0/ack", headers: service_headers

      expect(response).to have_http_status(:not_found)
    end
  end
end
