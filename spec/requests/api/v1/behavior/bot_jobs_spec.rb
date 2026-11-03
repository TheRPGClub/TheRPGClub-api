# frozen_string_literal: true

require "rails_helper"

# Behavior specs for the bot job queue: the API asks the bot to act in
# Discord. Jobs live in Postgres; a machine-local SQLite signal lets the bot
# poll often without waking Neon.
RSpec.describe "api/v1/bot_jobs behavior", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:requester) { create(:user) }

  # Each example starts as a fresh machine: no signal file, so it reads as up.
  before { FileUtils.rm_f(BotJob::WorkSignal.path) }

  # Postgres statements the block runs (the signal is raw SQLite, so it never
  # shows up here).
  def postgres_queries
    queries = []
    callback = ->(*, payload) { queries << payload[:sql] unless payload[:name] == "SCHEMA" }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { yield }
    queries
  end

  def poll(limit: nil)
    post "/api/v1/bot_jobs/claim#{"?limit=#{limit}" if limit}", headers: service_headers
    json.fetch("data")
  end

  def enqueue(kind: "giveaway_hub_refresh", payload: { "reason" => "donate" }, requested_by: requester)
    BotJob.enqueue!(kind: kind, payload: payload, requested_by: requested_by)
  end

  describe "POST /api/v1/bot_jobs/claim" do
    it "claims queued jobs for the service" do
      job = enqueue

      post "/api/v1/bot_jobs/claim", headers: service_headers

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data").sole).to include(
        "id" => job.id, "kind" => "giveaway_hub_refresh", "status" => "claimed", "attempts" => 1,
        "payload" => { "reason" => "donate" }, "requested_by_user_id" => requester.user_id
      )

      post "/api/v1/bot_jobs/claim", headers: service_headers
      expect(json.fetch("data")).to be_empty
    end

    it "makes no Postgres queries while the signal is down" do
      poll # a fresh machine checks Postgres once, finds nothing, lowers the signal

      queries = postgres_queries { poll }

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to be_empty
      expect(queries).to be_empty
    end

    it "raises the signal when a job is created" do
      poll
      job = enqueue

      expect(poll.map { |claimed| claimed["id"] }).to eq([ job.id ])
    end

    it "keeps the signal up while queued jobs remain" do
      poll
      first = enqueue
      second = enqueue

      expect(poll(limit: 1).map { |claimed| claimed["id"] }).to eq([ first.id ])
      expect(poll(limit: 1).map { |claimed| claimed["id"] }).to eq([ second.id ])
      expect(postgres_queries { poll }).to be_empty # the claim that emptied the queue lowered the signal
    end

    it "returns an unacked claim to the queue once its lease runs out" do
      job = enqueue
      poll

      travel(BotJob::LEASE - 1.second) { expect(poll).to be_empty }
      travel(BotJob::LEASE + 1.second) do
        expect(poll.sole).to include("id" => job.id, "status" => "claimed", "attempts" => 2)
      end
    end

    it "fails a job that times out on its last attempt" do
      job = enqueue
      BotJob::MAX_ATTEMPTS.times { |attempt| travel((BotJob::LEASE + 1.second) * attempt) { poll } }

      travel((BotJob::LEASE + 1.second) * BotJob::MAX_ATTEMPTS) { expect(poll).to be_empty }

      get "/api/v1/bot_jobs/#{job.id}", headers: service_headers
      expect(json.fetch("data")).to include(
        "status" => "failed", "attempts" => BotJob::MAX_ATTEMPTS, "error_message" => BotJob::TIMEOUT_ERROR
      )
    end

    it "honors ?limit" do
      3.times { enqueue }

      expect(poll(limit: 2).size).to eq(2)
    end

    it "is forbidden to admins and members" do
      post "/api/v1/bot_jobs/claim", headers: auth_headers_for(create(:user, role_admin: true))

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "POST /api/v1/bot_jobs/:id/done" do
    it "records the job done, idempotently" do
      job = enqueue
      poll

      2.times do
        post "/api/v1/bot_jobs/#{job.id}/done", headers: service_headers

        expect(response).to have_http_status(:ok)
        expect(json.fetch("data")).to include("id" => job.id, "status" => "done", "error_message" => nil)
        expect(json.dig("data", "finished_at")).to be_present
      end
    end

    it "stops a timed-out claim from being handed out again" do
      job = enqueue
      poll
      post "/api/v1/bot_jobs/#{job.id}/done", headers: service_headers

      travel(BotJob::LEASE + 1.second) { expect(poll).to be_empty }
    end

    it "conflicts with a job that already failed" do
      job = enqueue
      poll
      post "/api/v1/bot_jobs/#{job.id}/failed", params: { data: { error_message: "DMs closed" } }, headers: service_headers

      post "/api/v1/bot_jobs/#{job.id}/done", headers: service_headers

      expect(response).to have_http_status(:conflict)
    end

    it "404s for an unknown job" do
      post "/api/v1/bot_jobs/0/done", headers: service_headers

      expect(response).to have_http_status(:not_found)
    end

    it "is forbidden to the requesting member" do
      job = enqueue

      post "/api/v1/bot_jobs/#{job.id}/done", headers: auth_headers_for(requester)

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "POST /api/v1/bot_jobs/:id/failed" do
    it "records the failure and the bot's error" do
      job = enqueue
      poll

      post "/api/v1/bot_jobs/#{job.id}/failed", params: { data: { error_message: "DMs closed" } }, headers: service_headers

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("status" => "failed", "error_message" => "DMs closed")
    end

    it "requires an error message" do
      job = enqueue

      post "/api/v1/bot_jobs/#{job.id}/failed", params: { data: { error_message: "" } }, headers: service_headers

      expect(response).to have_http_status(:bad_request)
    end
  end

  describe "GET /api/v1/bot_jobs/:id" do
    let(:job) { enqueue(kind: "giveaway_claim_notice", payload: { "key" => "SECRET-KEY" }) }

    it "shows the requesting member their job's status, without the payload" do
      get "/api/v1/bot_jobs/#{job.id}", headers: auth_headers_for(requester)

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include(
        "id" => job.id, "kind" => "giveaway_claim_notice", "status" => "queued", "attempts" => 0,
        "requested_by_user_id" => requester.user_id, "error_message" => nil
      )
      expect(json.fetch("data")).not_to have_key("payload")
    end

    it "shows Admins and Superadmins any job" do
      get "/api/v1/bot_jobs/#{job.id}", headers: auth_headers_for(create(:user, role_admin: true))
      expect(response).to have_http_status(:ok)

      get "/api/v1/bot_jobs/#{job.id}", headers: auth_headers_for(create(:user), is_dev: true)
      expect(response).to have_http_status(:ok)
    end

    it "is forbidden to other members" do
      get "/api/v1/bot_jobs/#{job.id}", headers: auth_headers_for(create(:user))

      expect(response).to have_http_status(:forbidden)
    end

    it "is forbidden to members on a system job" do
      system_job = enqueue(kind: "voting_poll_wakeup", payload: {}, requested_by: nil)

      get "/api/v1/bot_jobs/#{system_job.id}", headers: auth_headers_for(create(:user))

      expect(response).to have_http_status(:forbidden)
    end

    it "401s without a token" do
      get "/api/v1/bot_jobs/#{job.id}"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "BotJob.enqueue!" do
    it "rejects an unknown kind" do
      expect { enqueue(kind: "nope") }.to raise_error(ActiveRecord::RecordInvalid)
    end

    it "leaves the signal down when the enqueue rolls back" do
      poll
      BotJob.transaction do
        enqueue
        raise ActiveRecord::Rollback
      end

      expect(postgres_queries { poll }).to be_empty
    end
  end
end
