# frozen_string_literal: true

require "rails_helper"

# Behavior specs for the bot-written journal message context endpoints:
# reads are open to any authenticated principal, the (channel_id, message_id)
# upsert and single delete are admin/service-only, and the bulk prune is
# service-only.
RSpec.describe "api/v1/journal_message_contexts behavior", type: :request do
  describe "GET /api/v1/journal_message_contexts" do
    it "lists contexts newest-first with all columns, filterable by channel_id" do
      channel = SecureRandom.random_number(10**18).to_s
      older = create(:journal_message_context, channel_id: channel, created_at_ms: 1_000)
      newer = create(:journal_message_context, channel_id: channel, created_at_ms: 2_000)
      create(:journal_message_context)

      get "/api/v1/journal_message_contexts",
        params: { channel_id: channel }, headers: auth_headers_for(create(:user))

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data").map { |c| c.fetch("message_id") }).to eq([ newer.message_id, older.message_id ])
      expect(json.fetch("data").first).to include(
        "channel_id" => channel,
        "message_id" => newer.message_id,
        "created_at_ms" => 2_000,
        "owner_user_id" => newer.owner_user_id,
        "game_id" => newer.game_id
      )
    end

    it "filters by created_after_ms (inclusive)" do
      channel = SecureRandom.random_number(10**18).to_s
      create(:journal_message_context, channel_id: channel, created_at_ms: 1_000)
      fresh = create(:journal_message_context, channel_id: channel, created_at_ms: 5_000)

      get "/api/v1/journal_message_contexts",
        params: { channel_id: channel, created_after_ms: 5_000 }, headers: service_headers

      expect(json.fetch("data").map { |c| c.fetch("message_id") }).to eq([ fresh.message_id ])
    end

    it "requires authentication" do
      get "/api/v1/journal_message_contexts"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "POST /api/v1/journal_message_contexts" do
    let(:game) { create(:game) }
    let(:payload) do
      { data: {
        channel_id: "chan-#{SecureRandom.hex(6)}",
        message_id: "msg-#{SecureRandom.hex(6)}",
        created_at_ms: 1_700_000_000_000,
        owner_user_id: "owner-#{SecureRandom.hex(4)}",
        game_id: game.game_id
      } }
    end

    it "creates a context as the service and returns 201" do
      expect {
        post "/api/v1/journal_message_contexts", params: payload, headers: service_headers, as: :json
      }.to change(JournalMessageContext, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(json.fetch("data")).to include(
        "channel_id" => payload[:data][:channel_id],
        "message_id" => payload[:data][:message_id],
        "created_at_ms" => 1_700_000_000_000,
        "owner_user_id" => payload[:data][:owner_user_id],
        "game_id" => game.game_id
      )
    end

    it "upserts on the composite key and returns 200 for an existing context" do
      post "/api/v1/journal_message_contexts", params: payload, headers: service_headers, as: :json
      updated = payload.deep_merge(data: { owner_user_id: "someone-else" })

      expect {
        post "/api/v1/journal_message_contexts", params: updated, headers: service_headers, as: :json
      }.not_to change(JournalMessageContext, :count)

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "owner_user_id")).to eq("someone-else")
      record = JournalMessageContext.find_by!(
        channel_id: payload[:data][:channel_id], message_id: payload[:data][:message_id]
      )
      expect(record.owner_user_id).to eq("someone-else")
    end

    it "allows an admin user" do
      post "/api/v1/journal_message_contexts",
        params: payload, headers: auth_headers_for(create(:user, :admin)), as: :json

      expect(response).to have_http_status(:created)
    end

    it "forbids a regular user" do
      expect {
        post "/api/v1/journal_message_contexts",
          params: payload, headers: auth_headers_for(create(:user)), as: :json
      }.not_to change(JournalMessageContext, :count)

      expect(response).to have_http_status(:forbidden)
    end

    it "400s when a composite-key part is missing" do
      post "/api/v1/journal_message_contexts",
        params: { data: payload[:data].except(:message_id) }, headers: service_headers, as: :json

      expect(response).to have_http_status(:bad_request)
    end

    it "422s when a required column is missing" do
      post "/api/v1/journal_message_contexts",
        params: { data: payload[:data].except(:owner_user_id) }, headers: service_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "requires authentication" do
      post "/api/v1/journal_message_contexts", params: payload, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "DELETE /api/v1/journal_message_contexts/:channel_id/:message_id" do
    it "deletes a context by its composite key as the service" do
      context_record = create(:journal_message_context)

      delete "/api/v1/journal_message_contexts/#{context_record.channel_id}/#{context_record.message_id}",
        headers: service_headers

      expect(response).to have_http_status(:ok)
      expect(json).to eq("deleted" => true)
      expect(
        JournalMessageContext.where(
          channel_id: context_record.channel_id, message_id: context_record.message_id
        ).exists?
      ).to be(false)
    end

    it "404s for an unknown composite key" do
      delete "/api/v1/journal_message_contexts/nope/nada", headers: service_headers

      expect(response).to have_http_status(:not_found)
    end

    it "forbids a regular user" do
      context_record = create(:journal_message_context)

      delete "/api/v1/journal_message_contexts/#{context_record.channel_id}/#{context_record.message_id}",
        headers: auth_headers_for(create(:user))

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "DELETE /api/v1/journal_message_contexts (prune)" do
    it "bulk-deletes contexts created strictly before the cutoff as the service" do
      channel = SecureRandom.random_number(10**18).to_s
      create(:journal_message_context, channel_id: channel, created_at_ms: 1_000)
      boundary = create(:journal_message_context, channel_id: channel, created_at_ms: 2_000)

      delete "/api/v1/journal_message_contexts", params: { before_ms: 2_000 }, headers: service_headers

      expect(response).to have_http_status(:ok)
      expect(json).to include("deleted" => true)
      expect(json.fetch("count")).to be >= 1
      expect(JournalMessageContext.where(channel_id: channel).pluck(:message_id))
        .to eq([ boundary.message_id ])
    end

    it "400s without before_ms" do
      delete "/api/v1/journal_message_contexts", headers: service_headers

      expect(response).to have_http_status(:bad_request)
    end

    it "forbids even an admin user (service-only)" do
      delete "/api/v1/journal_message_contexts",
        params: { before_ms: 1 }, headers: auth_headers_for(create(:user, :admin))

      expect(response).to have_http_status(:forbidden)
    end
  end
end
