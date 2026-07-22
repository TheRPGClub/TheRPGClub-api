# frozen_string_literal: true

require "rails_helper"

# Behavior specs for the game-key giveaway endpoints (bot parity, #42).
# Listings are open reads that never expose the secret `key_value`; the secret
# is revealed only via show (donor/claimer/admin/service) and the claim
# response. Donating is owner-only, revoking is donor/admin/service-only, and
# claiming atomically flips the unclaimed row.
RSpec.describe "api/v1/game_keys behavior", type: :request do
  let(:donor) { create(:user) }
  let(:claimant) { create(:user) }
  let(:other_user) { create(:user) }

  describe "GET /api/v1/game_keys" do
    it "lists only unclaimed keys, ordered by title, without the secret" do
      second = create(:game_key, game_title: "ordkey bbb", donor_user_id: donor.user_id)
      first = create(:game_key, game_title: "ORDKEY AAA", donor_user_id: donor.user_id)
      create(:game_key, game_title: "ordkey claimed", donor_user_id: donor.user_id,
        claimed_by_user_id: claimant.user_id, claimed_at: Time.current)

      get "/api/v1/game_keys", headers: auth_headers_for(other_user)

      expect(response).to have_http_status(:ok)
      ids = json.fetch("data").map { |k| k.fetch("key_id") }
      expect(ids).to eq([ first.key_id, second.key_id ])
      row = json.fetch("data").first
      expect(row).to include(
        "key_id" => first.key_id,
        "game_title" => "ORDKEY AAA",
        "platform" => first.platform,
        "donor_user_id" => donor.user_id,
        "claimed_by_user_id" => nil,
        "claimed_at" => nil,
        "donor_notify_on_claim" => false
      )
      expect(row).not_to have_key("key_value")
    end

    it "embeds the linked game and returns null for unlinked keys" do
      game = create(:game)
      linked = create(:game_key, gamedb_game_id: game.game_id, donor_user_id: donor.user_id)
      unlinked = create(:game_key, donor_user_id: donor.user_id)

      get "/api/v1/game_keys", headers: service_headers

      rows = json.fetch("data").index_by { |k| k.fetch("key_id") }
      expect(rows.fetch(linked.key_id).fetch("game")).to include("game_id" => game.game_id, "title" => game.title)
      expect(rows.fetch(unlinked.key_id).fetch("game")).to be_nil
    end

    it "requires authentication" do
      get "/api/v1/game_keys"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/users/:user_id/game_keys" do
    it "lists the user's donated keys (claimed included) newest first, without the secret" do
      older = create(:game_key, donor_user_id: donor.user_id)
      claimed = create(:game_key, donor_user_id: donor.user_id,
        claimed_by_user_id: claimant.user_id, claimed_at: Time.current)
      older.update_column(:created_at, 2.hours.ago)
      claimed.update_column(:created_at, 1.hour.ago)
      create(:game_key, donor_user_id: other_user.user_id)

      get "/api/v1/users/#{donor.user_id}/game_keys", headers: auth_headers_for(other_user)

      expect(response).to have_http_status(:ok)
      ids = json.fetch("data").map { |k| k.fetch("key_id") }
      expect(ids).to eq([ claimed.key_id, older.key_id ])
      expect(json.fetch("data").first).to include("claimed_by_user_id" => claimant.user_id)
      expect(json.fetch("data").first).not_to have_key("key_value")
    end

    it "requires authentication" do
      get "/api/v1/users/#{donor.user_id}/game_keys"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "POST /api/v1/game_keys" do
    let(:payload) do
      { data: { game_title: "Chrono Cross", platform: "PSN", key_value: "ABCD-EFGH",
                donor_user_id: donor.user_id, donor_notify_on_claim: true } }
    end

    it "donates a key as the donor themselves (secret not echoed back)" do
      expect {
        post "/api/v1/game_keys", params: payload, headers: auth_headers_for(donor), as: :json
      }.to change(RpgClubGameKey, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(json.fetch("data")).to include(
        "game_title" => "Chrono Cross",
        "platform" => "PSN",
        "donor_user_id" => donor.user_id,
        "donor_notify_on_claim" => true,
        "claimed_by_user_id" => nil
      )
      expect(json.fetch("data")).not_to have_key("key_value")
      expect(RpgClubGameKey.find(json.dig("data", "key_id")).key_value).to eq("ABCD-EFGH")
    end

    it "allows the service to donate on a user's behalf" do
      post "/api/v1/game_keys", params: payload, headers: service_headers, as: :json

      expect(response).to have_http_status(:created)
      expect(json.dig("data", "donor_user_id")).to eq(donor.user_id)
    end

    it "forbids donating as somebody else" do
      expect {
        post "/api/v1/game_keys", params: payload, headers: auth_headers_for(other_user), as: :json
      }.not_to change(RpgClubGameKey, :count)

      expect(response).to have_http_status(:forbidden)
    end

    it "forbids a Discord caller who names no donor" do
      post "/api/v1/game_keys",
        params: { data: { game_title: "X", platform: "Steam", key_value: "K" } },
        headers: auth_headers_for(donor), as: :json

      expect(response).to have_http_status(:forbidden)
    end

    it "ignores client-supplied claim fields" do
      payload[:data][:claimed_by_user_id] = other_user.user_id
      payload[:data][:claimed_at] = Time.current.iso8601

      post "/api/v1/game_keys", params: payload, headers: auth_headers_for(donor), as: :json

      expect(response).to have_http_status(:created)
      record = RpgClubGameKey.find(json.dig("data", "key_id"))
      expect(record.claimed_by_user_id).to be_nil
      expect(record.claimed_at).to be_nil
    end

    it "backfills game_title from the linked game when omitted" do
      game = create(:game)
      payload[:data].delete(:game_title)
      payload[:data][:gamedb_game_id] = game.game_id

      post "/api/v1/game_keys", params: payload, headers: auth_headers_for(donor), as: :json

      expect(response).to have_http_status(:created)
      expect(json.dig("data", "game_title")).to eq(game.title)
      expect(json.dig("data", "game")).to include("game_id" => game.game_id)
    end

    it "422s when platform is missing" do
      payload[:data].delete(:platform)

      post "/api/v1/game_keys", params: payload, headers: service_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "422s when neither game_title nor gamedb_game_id is given" do
      post "/api/v1/game_keys",
        params: { data: { platform: "Steam", key_value: "K", donor_user_id: donor.user_id } },
        headers: service_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "400s when the data envelope is missing" do
      post "/api/v1/game_keys", params: {}, headers: service_headers, as: :json

      expect(response).to have_http_status(:bad_request)
    end

    it "requires authentication" do
      post "/api/v1/game_keys", params: payload, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/game_keys/:id" do
    it "reveals the secret to the donor" do
      key = create(:game_key, donor_user_id: donor.user_id)

      get "/api/v1/game_keys/#{key.key_id}", headers: auth_headers_for(donor)

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("key_id" => key.key_id, "key_value" => key.key_value)
    end

    it "reveals the secret to an admin" do
      key = create(:game_key, donor_user_id: donor.user_id)

      get "/api/v1/game_keys/#{key.key_id}", headers: auth_headers_for(create(:user, :admin))

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "key_value")).to eq(key.key_value)
    end

    it "reveals the secret to the claimer of a claimed key" do
      key = create(:game_key, donor_user_id: donor.user_id,
        claimed_by_user_id: claimant.user_id, claimed_at: Time.current)

      get "/api/v1/game_keys/#{key.key_id}", headers: auth_headers_for(claimant)

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "key_value")).to eq(key.key_value)
    end

    it "reveals the secret to the service" do
      key = create(:game_key, donor_user_id: donor.user_id)

      get "/api/v1/game_keys/#{key.key_id}", headers: service_headers

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "key_value")).to eq(key.key_value)
    end

    it "forbids an unrelated user on an unclaimed key" do
      key = create(:game_key, donor_user_id: donor.user_id)

      get "/api/v1/game_keys/#{key.key_id}", headers: auth_headers_for(other_user)

      expect(response).to have_http_status(:forbidden)
      expect(json).to eq("error" => "forbidden")
    end

    it "forbids a non-claimer on a claimed key" do
      key = create(:game_key, donor_user_id: donor.user_id,
        claimed_by_user_id: claimant.user_id, claimed_at: Time.current)

      get "/api/v1/game_keys/#{key.key_id}", headers: auth_headers_for(other_user)

      expect(response).to have_http_status(:forbidden)
    end

    it "404s for an unknown id" do
      get "/api/v1/game_keys/999999999", headers: service_headers

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "DELETE /api/v1/game_keys/:id" do
    it "lets the donor revoke their key" do
      key = create(:game_key, donor_user_id: donor.user_id)

      delete "/api/v1/game_keys/#{key.key_id}", headers: auth_headers_for(donor)

      expect(response).to have_http_status(:ok)
      expect(json).to eq("deleted" => true)
      expect(RpgClubGameKey.exists?(key.key_id)).to be(false)
    end

    it "lets an admin revoke any key" do
      key = create(:game_key, donor_user_id: donor.user_id)

      delete "/api/v1/game_keys/#{key.key_id}", headers: auth_headers_for(create(:user, :admin))

      expect(response).to have_http_status(:ok)
      expect(RpgClubGameKey.exists?(key.key_id)).to be(false)
    end

    it "forbids the claimer (they receive the key, not control over it)" do
      key = create(:game_key, donor_user_id: donor.user_id,
        claimed_by_user_id: claimant.user_id, claimed_at: Time.current)

      delete "/api/v1/game_keys/#{key.key_id}", headers: auth_headers_for(claimant)

      expect(response).to have_http_status(:forbidden)
      expect(RpgClubGameKey.exists?(key.key_id)).to be(true)
    end

    it "forbids an unrelated user" do
      key = create(:game_key, donor_user_id: donor.user_id)

      delete "/api/v1/game_keys/#{key.key_id}", headers: auth_headers_for(other_user)

      expect(response).to have_http_status(:forbidden)
      expect(RpgClubGameKey.exists?(key.key_id)).to be(true)
    end

    it "404s for an unknown id" do
      delete "/api/v1/game_keys/999999999", headers: service_headers

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/v1/game_keys/:id/claim" do
    it "claims an unclaimed key for a Discord caller and reveals the secret" do
      key = create(:game_key, donor_user_id: donor.user_id)

      post "/api/v1/game_keys/#{key.key_id}/claim", headers: auth_headers_for(claimant), as: :json

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include(
        "key_id" => key.key_id,
        "key_value" => key.key_value,
        "claimed_by_user_id" => claimant.user_id
      )
      key.reload
      expect(key.claimed_by_user_id).to eq(claimant.user_id)
      expect(key.claimed_at).to be_present
    end

    it "records the claim against the caller even when the body names someone else" do
      key = create(:game_key, donor_user_id: donor.user_id)

      post "/api/v1/game_keys/#{key.key_id}/claim",
        params: { data: { claimed_by_user_id: other_user.user_id } },
        headers: auth_headers_for(claimant), as: :json

      expect(response).to have_http_status(:ok)
      expect(key.reload.claimed_by_user_id).to eq(claimant.user_id)
    end

    it "lets the service claim on behalf of a named user" do
      key = create(:game_key, donor_user_id: donor.user_id)

      post "/api/v1/game_keys/#{key.key_id}/claim",
        params: { data: { claimed_by_user_id: claimant.user_id } }, headers: service_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "key_value")).to eq(key.key_value)
      expect(key.reload.claimed_by_user_id).to eq(claimant.user_id)
    end

    it "422s when the service names no claimant" do
      key = create(:game_key, donor_user_id: donor.user_id)

      post "/api/v1/game_keys/#{key.key_id}/claim", headers: service_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json).to eq("error" => "claimant_required")
      expect(key.reload.claimed_by_user_id).to be_nil
    end

    it "409s when the key is already claimed" do
      key = create(:game_key, donor_user_id: donor.user_id,
        claimed_by_user_id: claimant.user_id, claimed_at: Time.current)

      post "/api/v1/game_keys/#{key.key_id}/claim", headers: auth_headers_for(other_user), as: :json

      expect(response).to have_http_status(:conflict)
      expect(json).to eq("error" => "already_claimed")
      expect(key.reload.claimed_by_user_id).to eq(claimant.user_id)
    end

    it "404s for an unknown key" do
      post "/api/v1/game_keys/999999999/claim", headers: auth_headers_for(claimant), as: :json

      expect(response).to have_http_status(:not_found)
    end

    it "requires authentication" do
      key = create(:game_key, donor_user_id: donor.user_id)

      post "/api/v1/game_keys/#{key.key_id}/claim", as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
