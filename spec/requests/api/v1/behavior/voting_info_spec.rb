# frozen_string_literal: true

require "rails_helper"

# Behavior specs for the voting_info endpoints: bot-managed voting round
# metadata, open to any authenticated caller (reads AND writes — the
# documented contract has no admin gate), plus the derived voting-window
# fields (vote_deadline / voting_open / voting_ended) computed off
# next_vote_at and the optional vote_ends_at override.
RSpec.describe "api/v1/voting_info behavior", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  # Fixed timeline: voting opens Friday 2026-06-05 17:00 UTC, so the default
  # deadline is the end of Sunday 2026-06-07 US Eastern (2026-06-08 03:59 UTC).
  let(:opens_at) { Time.utc(2026, 6, 5, 17, 0, 0) }
  let(:default_deadline) { Time.utc(2026, 6, 8, 3, 59, 59) }
  let(:member) { create(:user) }

  describe "GET /api/v1/voting_info" do
    it "lists rounds newest first with the raw and derived fields" do
      low = create(:voting_info)
      high = create(:voting_info, round_number: low.round_number + 1, nomination_list_id: 42)

      get "/api/v1/voting_info", headers: auth_headers_for(member)

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data").map { |r| r.fetch("round_number") })
        .to eq([ high.round_number, low.round_number ])
      expect(json.fetch("data").first).to include(
        "round_number" => high.round_number,
        "nomination_list_id" => 42,
        "five_day_reminder_sent" => false,
        "one_day_reminder_sent" => false,
        "vote_ends_at" => nil
      )
      expect(json.fetch("data").first).to include("vote_deadline", "voting_open", "voting_ended")
      expect(json.fetch("meta")).to include("page" => 1, "count" => 2)
    end

    it "requires authentication" do
      get "/api/v1/voting_info"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/voting_info/current" do
    it "returns the round with the highest round_number" do
      low = create(:voting_info)
      high = create(:voting_info, round_number: low.round_number + 1)

      get "/api/v1/voting_info/current", headers: auth_headers_for(member)

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "round_number")).to eq(high.round_number)
    end

    it "404s when no rounds exist" do
      get "/api/v1/voting_info/current", headers: service_headers

      expect(response).to have_http_status(:not_found)
      expect(json).to have_key("error")
    end
  end

  describe "GET /api/v1/voting_info/:id" do
    it "reports an open window with the default Friday-to-Sunday deadline while voting runs" do
      info = create(:voting_info, next_vote_at: opens_at)

      travel_to(Time.utc(2026, 6, 6, 12)) do
        get "/api/v1/voting_info/#{info.round_number}", headers: auth_headers_for(member)
      end

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("voting_open" => true, "voting_ended" => false)
      expect(Time.zone.parse(json.dig("data", "vote_deadline")).to_i).to eq(default_deadline.to_i)
      expect(Time.zone.parse(json.dig("data", "next_vote_at")).to_i).to eq(opens_at.to_i)
    end

    it "reports a closed, ended window after the deadline" do
      info = create(:voting_info, next_vote_at: opens_at)

      travel_to(Time.utc(2026, 6, 9, 12)) do
        get "/api/v1/voting_info/#{info.round_number}", headers: auth_headers_for(member)
      end

      expect(json.fetch("data")).to include("voting_open" => false, "voting_ended" => true)
    end

    it "uses the explicit vote_ends_at override as the deadline" do
      override = Time.utc(2026, 6, 12, 17, 0, 0)
      info = create(:voting_info, next_vote_at: opens_at, vote_ends_at: override)

      travel_to(Time.utc(2026, 6, 9, 12)) do
        get "/api/v1/voting_info/#{info.round_number}", headers: auth_headers_for(member)
      end

      expect(json.fetch("data")).to include("voting_open" => true, "voting_ended" => false)
      expect(Time.zone.parse(json.dig("data", "vote_deadline")).to_i).to eq(override.to_i)
    end

    it "404s for an unknown round" do
      get "/api/v1/voting_info/999999999", headers: service_headers

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/v1/voting_info" do
    let(:round) { SecureRandom.random_number(1_000_000_000) }
    let(:payload) { { data: { round_number: round, next_vote_at: opens_at.iso8601 } } }

    it "creates a round as the service with defaulted reminder flags" do
      expect {
        post "/api/v1/voting_info", params: payload, headers: service_headers, as: :json
      }.to change(BotVotingInfo, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(json.fetch("data")).to include(
        "round_number" => round,
        "five_day_reminder_sent" => false,
        "one_day_reminder_sent" => false
      )
      expect(BotVotingInfo.find(round).next_vote_at.to_i).to eq(opens_at.to_i)
    end

    it "is open to a regular authenticated user (documented: no admin gate)" do
      post "/api/v1/voting_info", params: payload, headers: auth_headers_for(member), as: :json

      expect(response).to have_http_status(:created)
    end

    it "422s for a duplicate round_number" do
      pending "possible bug: bot_voting_info has no PK/unique constraint (only the non-unique " \
        "ix_bot_voting_info_round index), so POSTing an existing round_number inserts a second " \
        "row and returns 201 instead of the documented 422"
      create(:voting_info, round_number: round)

      expect {
        post "/api/v1/voting_info", params: payload, headers: service_headers, as: :json
      }.not_to change(BotVotingInfo, :count)

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "422s when next_vote_at is missing" do
      pending "possible bug: BotVotingInfo has no presence validation, so the NOT NULL " \
        "next_vote_at column raises ActiveRecord::NotNullViolation and returns 500 instead of " \
        "the documented 422 (other models presence-validate to avoid exactly this)"
      post "/api/v1/voting_info", params: { data: { round_number: round } },
        headers: service_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "400s when the data envelope is missing" do
      post "/api/v1/voting_info", params: { round_number: round }, headers: service_headers, as: :json

      expect(response).to have_http_status(:bad_request)
    end

    it "requires authentication" do
      post "/api/v1/voting_info", params: payload, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "PATCH /api/v1/voting_info/:id" do
    it "partially updates the round" do
      info = create(:voting_info)
      ends_at = 3.days.from_now.change(usec: 0)

      patch "/api/v1/voting_info/#{info.round_number}",
        params: { data: { five_day_reminder_sent: true, vote_ends_at: ends_at.iso8601 } },
        headers: auth_headers_for(member), as: :json

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("five_day_reminder_sent" => true)
      expect(info.reload.five_day_reminder_sent).to be(true)
      expect(info.vote_ends_at.to_i).to eq(ends_at.to_i)
    end

    it "accepts PUT as an alias" do
      info = create(:voting_info)

      put "/api/v1/voting_info/#{info.round_number}",
        params: { data: { one_day_reminder_sent: true } }, headers: service_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(info.reload.one_day_reminder_sent).to be(true)
    end

    it "404s for an unknown round" do
      patch "/api/v1/voting_info/999999999",
        params: { data: { five_day_reminder_sent: true } }, headers: service_headers, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it "requires authentication" do
      patch "/api/v1/voting_info/1", params: { data: { five_day_reminder_sent: true } }, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "DELETE /api/v1/voting_info/:id" do
    it "deletes the round" do
      info = create(:voting_info)

      delete "/api/v1/voting_info/#{info.round_number}", headers: auth_headers_for(member)

      expect(response).to have_http_status(:ok)
      expect(json).to eq("deleted" => true)
      expect(BotVotingInfo.exists?(info.round_number)).to be(false)
    end

    it "404s for an unknown round" do
      delete "/api/v1/voting_info/999999999", headers: service_headers

      expect(response).to have_http_status(:not_found)
    end

    it "requires authentication" do
      delete "/api/v1/voting_info/1"

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
