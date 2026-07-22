# frozen_string_literal: true

require "rails_helper"

# Behavior specs for session management (Auth::SessionsController#destroy) and
# the UserSessionToken lifecycle around it: logout revokes exactly the
# presented bearer token, and tokens expire seven days after issue (enforced
# by the user_session_token warden strategy).
RSpec.describe "auth/sessions behavior", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user) }

  describe "DELETE /auth/logout" do
    it "revokes the bearer session token and returns ok" do
      headers = auth_headers_for(user)

      expect {
        delete "/auth/logout", headers: headers
      }.to change(UserSessionToken.where(user_id: user.user_id), :count).by(-1)

      expect(response).to have_http_status(:ok)
      expect(json).to eq("ok" => true)
    end

    it "invalidates the token for subsequent authenticated calls" do
      headers = auth_headers_for(user)

      get "/api/v1/session", headers: headers
      expect(response).to have_http_status(:ok)

      delete "/auth/logout", headers: headers

      get "/api/v1/session", headers: headers
      expect(response).to have_http_status(:unauthorized)
      expect(json).to eq("error" => "unauthorized")
    end

    it "revokes only the presented token, keeping the user's other sessions valid" do
      revoked_headers = auth_headers_for(user)
      kept_headers = auth_headers_for(user)

      delete "/auth/logout", headers: revoked_headers

      get "/api/v1/session", headers: kept_headers
      expect(response).to have_http_status(:ok)
    end

    it "succeeds when called without any credentials" do
      delete "/auth/logout"

      expect(response).to have_http_status(:ok)
      expect(json).to eq("ok" => true)
    end

    it "succeeds for an unknown bearer token without revoking anything" do
      auth_headers_for(user)

      expect {
        delete "/auth/logout", headers: { "Authorization" => "Bearer not-a-real-token" }
      }.not_to change(UserSessionToken, :count)

      expect(response).to have_http_status(:ok)
      expect(json).to eq("ok" => true)
    end

    it "succeeds for the service token, which has no session-token row" do
      expect {
        delete "/auth/logout", headers: service_headers
      }.not_to change(UserSessionToken, :count)

      expect(response).to have_http_status(:ok)
      expect(json).to eq("ok" => true)
    end

    it "deletes the row even when the presented token has already expired" do
      headers = auth_headers_for(user)

      travel_to(8.days.from_now) do
        expect {
          delete "/auth/logout", headers: headers
        }.to change(UserSessionToken, :count).by(-1)

        expect(response).to have_http_status(:ok)
        expect(json).to eq("ok" => true)
      end
    end
  end

  describe "session token expiry" do
    it "accepts a session token within its 7-day lifetime" do
      headers = auth_headers_for(user)

      travel_to(6.days.from_now) do
        get "/api/v1/session", headers: headers

        expect(response).to have_http_status(:ok)
        expect(json.dig("principal", "id")).to eq(user.user_id)
      end
    end

    it "rejects a session token after its 7-day expiry" do
      headers = auth_headers_for(user)

      travel_to(7.days.from_now + 1.minute) do
        get "/api/v1/session", headers: headers

        expect(response).to have_http_status(:unauthorized)
        expect(json).to eq("error" => "unauthorized")
      end
    end

    it "purges a user's expired tokens when a new one is issued" do
      stale_headers = auth_headers_for(user)

      travel_to(8.days.from_now) do
        fresh_headers = auth_headers_for(user)

        expect(UserSessionToken.where(user_id: user.user_id).count).to eq(1)

        get "/api/v1/session", headers: stale_headers
        expect(response).to have_http_status(:unauthorized)

        get "/api/v1/session", headers: fresh_headers
        expect(response).to have_http_status(:ok)
      end
    end
  end
end
