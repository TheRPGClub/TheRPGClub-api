# frozen_string_literal: true

require "rails_helper"

# Behavior specs for the admin-wizard session endpoints (#162). Every route is
# owner-only (the service token counts as the owner).
#
# NOTE: the DB check constraint (ck_rpg_club_admin_wiz_sess_status) only
# accepts the uppercase ACTIVE/COMPLETED/CANCELLED statuses the Discord bot
# writes, while the Rails model validates — and the controller queries/writes —
# the lowercase active/completed/cancelled. Every write of a status therefore
# violates the constraint (500), and every status query misses the bot's
# uppercase rows. The affected examples are marked pending and assert the
# documented contract; seeded rows use the uppercase statuses production
# actually contains (see the :wizard_session factory).
RSpec.describe "api/v1/wizard_sessions behavior", type: :request do
  let(:owner) { create(:user) }
  let(:other_user) { create(:user) }

  describe "GET /api/v1/users/:user_id/wizard_sessions" do
    it "returns the active session for the (command_key, owner, channel)" do
      pending "possible bug: the controller queries status: 'active' but the DB check constraint " \
              "only allows the bot's uppercase 'ACTIVE', so the active session is never found (404)"

      session = create(:wizard_session, owner_user_id: owner.user_id)

      get "/api/v1/users/#{owner.user_id}/wizard_sessions",
        params: { command_key: session.command_key, channel_id: session.channel_id },
        headers: auth_headers_for(owner)

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include(
        "session_id" => session.session_id,
        "command_key" => session.command_key,
        "owner_user_id" => owner.user_id,
        "channel_id" => session.channel_id,
        "state_json" => session.state_json
      )
    end

    it "404s when no active session exists" do
      get "/api/v1/users/#{owner.user_id}/wizard_sessions",
        params: { command_key: "nextround-setup", channel_id: "12345" }, headers: service_headers

      expect(response).to have_http_status(:not_found)
      expect(json).to have_key("error")
    end

    it "400s when command_key is missing" do
      get "/api/v1/users/#{owner.user_id}/wizard_sessions",
        params: { channel_id: "12345" }, headers: auth_headers_for(owner)

      expect(response).to have_http_status(:bad_request)
    end

    it "forbids another user" do
      get "/api/v1/users/#{owner.user_id}/wizard_sessions",
        params: { command_key: "nextround-setup", channel_id: "12345" }, headers: auth_headers_for(other_user)

      expect(response).to have_http_status(:forbidden)
      expect(json).to eq("error" => "forbidden")
    end

    it "requires authentication" do
      get "/api/v1/users/#{owner.user_id}/wizard_sessions",
        params: { command_key: "nextround-setup", channel_id: "12345" }

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "POST /api/v1/users/:user_id/wizard_sessions (upsert)" do
    let(:payload) do
      { data: { command_key: "nextround-setup", channel_id: "999888", guild_id: "1", state_json: '{"step":2}' } }
    end

    it "creates the active session for the owner" do
      pending "possible bug: the model writes status 'active' but the DB check constraint only " \
              "allows uppercase 'ACTIVE', so every upsert fails the constraint and renders 500"

      expect {
        post "/api/v1/users/#{owner.user_id}/wizard_sessions",
          params: payload, headers: auth_headers_for(owner), as: :json
      }.to change(RpgClubAdminWizardSession, :count).by(1)

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include(
        "command_key" => "nextround-setup",
        "owner_user_id" => owner.user_id,
        "channel_id" => "999888",
        "state_json" => '{"step":2}'
      )
    end

    it "reuses the existing active session's session_id" do
      pending "possible bug: the upsert looks up status: 'active' (missing the stored uppercase " \
              "'ACTIVE' row) and then fails the status check constraint on insert (500)"

      session = create(:wizard_session, owner_user_id: owner.user_id,
        command_key: "nextround-setup", channel_id: "999888")

      expect {
        post "/api/v1/users/#{owner.user_id}/wizard_sessions",
          params: payload, headers: auth_headers_for(owner), as: :json
      }.not_to change(RpgClubAdminWizardSession, :count)

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "session_id")).to eq(session.session_id)
      expect(session.reload.state_json).to eq('{"step":2}')
    end

    it "400s when state_json is missing" do
      post "/api/v1/users/#{owner.user_id}/wizard_sessions",
        params: { data: { command_key: "nextround-setup", channel_id: "999888" } },
        headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:bad_request)
      expect(json.fetch("error")).to include("state_json")
    end

    it "forbids another user" do
      expect {
        post "/api/v1/users/#{owner.user_id}/wizard_sessions",
          params: payload, headers: auth_headers_for(other_user), as: :json
      }.not_to change(RpgClubAdminWizardSession, :count)

      expect(response).to have_http_status(:forbidden)
    end

    it "requires authentication" do
      post "/api/v1/users/#{owner.user_id}/wizard_sessions", params: payload, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "PATCH /api/v1/wizard_sessions/:id" do
    it "promotes the session to completed for the owner" do
      pending "possible bug: the model writes status 'completed' but the DB check constraint only " \
              "allows uppercase 'COMPLETED', so the transition fails the constraint and renders 500"

      session = create(:wizard_session, owner_user_id: owner.user_id)

      patch "/api/v1/wizard_sessions/#{session.session_id}",
        params: { data: { status: "completed" } }, headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "status")).to eq("completed")
      expect(session.reload.status).to eq("completed")
    end

    it "422s for a status outside the allowed set" do
      session = create(:wizard_session, owner_user_id: owner.user_id)

      patch "/api/v1/wizard_sessions/#{session.session_id}",
        params: { data: { status: "bogus" } }, headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "400s when status is blank" do
      session = create(:wizard_session, owner_user_id: owner.user_id)

      patch "/api/v1/wizard_sessions/#{session.session_id}",
        params: { data: { status: "" } }, headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:bad_request)
      expect(json.fetch("error")).to include("status")
    end

    it "forbids a non-owner" do
      session = create(:wizard_session, owner_user_id: owner.user_id)

      patch "/api/v1/wizard_sessions/#{session.session_id}",
        params: { data: { status: "cancelled" } }, headers: auth_headers_for(other_user), as: :json

      expect(response).to have_http_status(:forbidden)
      expect(session.reload.status).to eq("ACTIVE")
    end

    it "404s for an unknown id" do
      patch "/api/v1/wizard_sessions/unknown-session",
        params: { data: { status: "cancelled" } }, headers: service_headers, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it "requires authentication" do
      patch "/api/v1/wizard_sessions/whatever", params: { data: { status: "cancelled" } }, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "DELETE /api/v1/wizard_sessions/:id" do
    it "deletes the owner's session" do
      session = create(:wizard_session, owner_user_id: owner.user_id)

      delete "/api/v1/wizard_sessions/#{session.session_id}", headers: auth_headers_for(owner)

      expect(response).to have_http_status(:ok)
      expect(json).to eq("deleted" => true)
      expect(RpgClubAdminWizardSession.exists?(session.session_id)).to be(false)
    end

    it "allows the service" do
      session = create(:wizard_session, owner_user_id: owner.user_id)

      delete "/api/v1/wizard_sessions/#{session.session_id}", headers: service_headers

      expect(response).to have_http_status(:ok)
      expect(RpgClubAdminWizardSession.exists?(session.session_id)).to be(false)
    end

    it "forbids a non-owner" do
      session = create(:wizard_session, owner_user_id: owner.user_id)

      delete "/api/v1/wizard_sessions/#{session.session_id}", headers: auth_headers_for(other_user)

      expect(response).to have_http_status(:forbidden)
      expect(RpgClubAdminWizardSession.exists?(session.session_id)).to be(true)
    end

    it "404s for an unknown id" do
      delete "/api/v1/wizard_sessions/unknown-session", headers: service_headers

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "DELETE /api/v1/users/:user_id/wizard_sessions (historical)" do
    it "deletes the historical sessions for the (command_key, owner, channel)" do
      create(:wizard_session, :completed, owner_user_id: owner.user_id,
        command_key: "nextround-setup", channel_id: "555")
      create(:wizard_session, :cancelled, owner_user_id: owner.user_id,
        command_key: "nextround-setup", channel_id: "555")
      other_channel = create(:wizard_session, :completed, owner_user_id: owner.user_id,
        command_key: "nextround-setup", channel_id: "666")

      delete "/api/v1/users/#{owner.user_id}/wizard_sessions",
        params: { command_key: "nextround-setup", channel_id: "555" }, headers: auth_headers_for(owner)

      expect(response).to have_http_status(:ok)
      expect(json).to eq("deleted" => true, "count" => 2)
      expect(RpgClubAdminWizardSession.exists?(other_channel.session_id)).to be(true)
    end

    it "keeps the active session" do
      pending "possible bug: where.not(status: 'active') does not exclude the stored uppercase " \
              "'ACTIVE' rows, so the active session is deleted along with the historical ones"

      active = create(:wizard_session, owner_user_id: owner.user_id,
        command_key: "nextround-setup", channel_id: "555")
      create(:wizard_session, :completed, owner_user_id: owner.user_id,
        command_key: "nextround-setup", channel_id: "555")

      delete "/api/v1/users/#{owner.user_id}/wizard_sessions",
        params: { command_key: "nextround-setup", channel_id: "555" }, headers: auth_headers_for(owner)

      expect(response).to have_http_status(:ok)
      expect(json).to eq("deleted" => true, "count" => 1)
      expect(RpgClubAdminWizardSession.exists?(active.session_id)).to be(true)
    end

    it "400s when channel_id is missing" do
      delete "/api/v1/users/#{owner.user_id}/wizard_sessions",
        params: { command_key: "nextround-setup" }, headers: auth_headers_for(owner)

      expect(response).to have_http_status(:bad_request)
    end

    it "forbids another user" do
      session = create(:wizard_session, :completed, owner_user_id: owner.user_id,
        command_key: "nextround-setup", channel_id: "555")

      delete "/api/v1/users/#{owner.user_id}/wizard_sessions",
        params: { command_key: "nextround-setup", channel_id: "555" }, headers: auth_headers_for(other_user)

      expect(response).to have_http_status(:forbidden)
      expect(RpgClubAdminWizardSession.exists?(session.session_id)).to be(true)
    end

    it "requires authentication" do
      delete "/api/v1/users/#{owner.user_id}/wizard_sessions",
        params: { command_key: "nextround-setup", channel_id: "555" }

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
