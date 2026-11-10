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

  def enqueue(kind: "giveaway_hub_refresh", payload: { "reason" => "donate" }, requested_by: requester,
    summary: "Refresh the giveaway hub")
    BotJob.enqueue!(kind: kind, summary: summary, payload: payload, requested_by: requested_by)
  end

  describe "POST /api/v1/bot_jobs/claim" do
    it "claims queued jobs for the service" do
      job = enqueue

      post "/api/v1/bot_jobs/claim", headers: service_headers

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data").sole).to include(
        "id" => job.id, "kind" => "giveaway_hub_refresh", "status" => "claimed", "attempts" => 1,
        "payload" => { "reason" => "donate", "feature_key" => "giveaways" },
        "requested_by_user_id" => requester.user_id
      )

      post "/api/v1/bot_jobs/claim", headers: service_headers
      expect(json.fetch("data")).to be_empty
    end

    # Public posts carry the Feature that owns them, so the bot can route them
    # by its Feature Flag (bot-dev channel in Preview, nowhere when Off).
    {
      "completion_announce" => "game_completions",
      "nomination_deleted" => "voting_gotm",
      "voting_results_publish" => "voting_gotm",
      "voting_panels_repost" => "voting_gotm",
      "voting_tie_broken" => "voting_gotm",
      "suggestion_outcome" => "suggestions",
      "suggestion_submitted" => "suggestions",
      "giveaway_hub_refresh" => "giveaways",
      "giveaway_claim_notice" => "giveaways"
    }.each do |kind, feature_key|
      it "gives a #{kind} job its Feature key, #{feature_key}" do
        enqueue(kind: kind, payload: { round_number: 7 })

        expect(poll.sole.fetch("payload")).to eq("round_number" => 7, "feature_key" => feature_key)
      end
    end

    # Work a Feature owns that posts nothing carries the key too.
    {
      "news_images_renew" => "news_hub",
      "news_catch_up" => "news_hub"
    }.each do |kind, feature_key|
      it "gives a #{kind} job, which does #{feature_key}'s work, its Feature key" do
        enqueue(kind: kind, payload: { round_number: 7 })

        expect(poll.sole.fetch("payload")).to eq("round_number" => 7, "feature_key" => feature_key)
      end
    end

    %w[
      voting_poll_wakeup gotm_cache_reload
      live_event_create say memberscan presence_set
    ].each do |kind|
      it "gives a #{kind} job, which posts nothing publicly, no Feature key" do
        enqueue(kind: kind, payload: { round_number: 7 })

        expect(poll.sole.fetch("payload")).to eq("round_number" => 7)
      end
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

    it "gives a kind with its own lease that long before handing it out again" do
      stub_const("BotJob::LEASES", { "suggestion_submitted" => 30.minutes })
      long = enqueue(kind: "suggestion_submitted", payload: {})
      short = enqueue
      claimed = poll

      expect(claimed.to_h { |job| [ job["id"], Time.zone.parse(job["lease_expires_at"]) - Time.zone.parse(job["claimed_at"]) ] })
        .to eq(long.id => 30.minutes.to_f, short.id => 5.minutes.to_f)
      travel(BotJob::LEASE + 1.second) do
        expect(poll.map { |job| job["id"] }).to eq([ short.id ])
        post "/api/v1/bot_jobs/#{short.id}/done", headers: service_headers
      end
      travel(30.minutes - 1.second) { expect(poll.map { |job| job["id"] }).to eq([]) }
      travel(30.minutes + 1.second) { expect(poll.map { |job| job["id"] }).to eq([ long.id ]) }
    end

    it "wakes the lowered signal when the earliest lease runs out" do
      stub_const("BotJob::LEASES", { "suggestion_submitted" => 30.minutes })
      job = enqueue(kind: "suggestion_submitted", payload: {})
      poll

      travel(20.minutes) { expect(postgres_queries { poll }).to be_empty }
      travel(30.minutes + 1.second) { expect(poll.sole).to include("id" => job.id, "attempts" => 2) }
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

    # Deploy window: the old release claims without a lease expiry (claimed_at
    # only). Such a claim expires at claimed_at plus the default lease.
    context "with a claim made before per-claim leases" do
      def claim_the_old_way(job, at: Time.current)
        job.update_columns(status: "claimed", claimed_at: at, lease_expires_at: nil, attempts: job.attempts + 1)
      end

      it "returns it to the queue once the default lease runs out" do
        job = enqueue
        claim_the_old_way(job)

        travel(BotJob::LEASE - 1.second) { expect(poll).to be_empty }
        travel(BotJob::LEASE + 1.second) { expect(poll.sole).to include("id" => job.id, "attempts" => 2) }
      end

      it "fails it once it has used every attempt" do
        job = enqueue
        job.update_columns(attempts: BotJob::MAX_ATTEMPTS - 1)
        claim_the_old_way(job)

        travel(BotJob::LEASE + 1.second) { expect(poll).to be_empty }
        expect(job.reload).to have_attributes(status: "failed", error_message: BotJob::TIMEOUT_ERROR)
      end

      it "wakes the lowered signal when that default lease runs out" do
        job = enqueue
        claim_the_old_way(job)
        poll # nothing queued: lowers the signal

        travel(BotJob::LEASE - 1.minute) { expect(postgres_queries { poll }).to be_empty }
        travel(BotJob::LEASE + 1.second) { expect(poll.sole).to include("id" => job.id) }
      end
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

    it "stores the bot's result text and returns it with the job" do
      job = enqueue
      poll

      post "/api/v1/bot_jobs/#{job.id}/done", params: { data: { result_text: "Upserted 120, departed 3" } },
        headers: service_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("status" => "done", "result_text" => "Upserted 120, departed 3")
      get "/api/v1/bot_jobs/#{job.id}", headers: auth_headers_for(requester)
      expect(json.dig("data", "result_text")).to eq("Upserted 120, departed 3")
    end

    it "keeps the first result on a repeated ack" do
      job = enqueue
      poll
      post "/api/v1/bot_jobs/#{job.id}/done", params: { data: { result_text: "first" } }, headers: service_headers,
        as: :json

      post "/api/v1/bot_jobs/#{job.id}/done", params: { data: { result_text: "second" } }, headers: service_headers,
        as: :json

      expect(json.dig("data", "result_text")).to eq("first")
    end

    it "cuts a result text over #{BotJob::TEXT_MAX} characters rather than failing the ack" do
      job = enqueue
      poll

      post "/api/v1/bot_jobs/#{job.id}/done", params: { data: { result_text: "x" * (BotJob::TEXT_MAX + 1) } },
        headers: service_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "status")).to eq("done")
      expect(json.dig("data", "result_text").length).to eq(BotJob::TEXT_MAX)
      travel(BotJob::LEASE + 1.second) { expect(poll).to be_empty }
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

    it "cuts an error message over #{BotJob::TEXT_MAX} characters rather than failing the ack" do
      job = enqueue
      poll

      post "/api/v1/bot_jobs/#{job.id}/failed", params: { data: { error_message: "e" * (BotJob::TEXT_MAX + 1) } },
        headers: service_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "status")).to eq("failed")
      expect(json.dig("data", "error_message").length).to eq(BotJob::TEXT_MAX)
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
        "requested_by_user_id" => requester.user_id, "error_message" => nil,
        "summary" => "Refresh the giveaway hub", "result_text" => nil
      )
      expect(json.dig("data", "requested_by")).to include("user_id" => requester.user_id, "username" => requester.username)
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

  describe "GET /api/v1/bot_jobs" do
    let(:moderator) { create(:user, role_moderator: true, username: "modname") }
    let!(:member_job) { enqueue(payload: { "key" => "SECRET-KEY" }) }
    let!(:system_job) { enqueue(kind: "voting_poll_wakeup", payload: {}, requested_by: nil, summary: "Wake the poller") }
    let!(:moderator_job) { enqueue(requested_by: moderator, summary: "Set the presence") }

    def list(headers, **params)
      get "/api/v1/bot_jobs", params: params, headers: headers
    end

    def listed_ids = json.fetch("data").map { |job| job["id"] }

    {
      "an Admin" => [ { role_admin: true }, {} ],
      "a Superadmin" => [ {}, { is_dev: true } ]
    }.each do |label, (flags, token_flags)|
      it "shows #{label} every job, newest first" do
        list(auth_headers_for(create(:user, **flags), **token_flags))

        expect(response).to have_http_status(:ok)
        expect(listed_ids).to eq([ moderator_job.id, system_job.id, member_job.id ])
      end
    end

    it "shows the service every job" do
      list(service_headers)

      expect(listed_ids).to eq([ moderator_job.id, system_job.id, member_job.id ])
    end

    it "shows a Moderator only the jobs they requested" do
      list(auth_headers_for(moderator))

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data").sole).to include(
        "id" => moderator_job.id, "kind" => "giveaway_hub_refresh", "summary" => "Set the presence",
        "status" => "queued", "requested_by_user_id" => moderator.user_id, "error_message" => nil,
        "result_text" => nil
      )
      expect(json.dig("data", 0, "requested_by")).to include("user_id" => moderator.user_id, "username" => "modname")
      expect(json.fetch("meta")).to include("count" => 1, "page" => 1)
    end

    it "shows the bot's error and result, never the payload" do
      poll
      post "/api/v1/bot_jobs/#{member_job.id}/failed", params: { data: { error_message: "DMs closed" } },
        headers: service_headers
      post "/api/v1/bot_jobs/#{moderator_job.id}/done", params: { data: { result_text: "Presence set" } },
        headers: service_headers

      list(auth_headers_for(create(:user, role_admin: true)))

      rows = json.fetch("data").index_by { |job| job["id"] }
      expect(rows.fetch(member_job.id)).to include("status" => "failed", "error_message" => "DMs closed")
      expect(rows.fetch(moderator_job.id)).to include("status" => "done", "result_text" => "Presence set")
      expect(rows.fetch(system_job.id)).to include("requested_by" => nil, "requested_by_user_id" => nil)
      expect(json.fetch("data")).to all(satisfy { |job| !job.key?("payload") })
      expect(response.body).not_to include("SECRET-KEY")
    end

    it "pages with ?page and ?per" do
      list(service_headers, per: 2, page: 2)

      expect(listed_ids).to eq([ member_job.id ])
      expect(json.fetch("meta")).to include("page" => 2, "pages" => 2, "count" => 3, "per" => 2)
    end

    {
      "a plain member" => {},
      "a Members role holder" => { role_member: true },
      "a Regulars role holder" => { role_regular: true }
    }.each do |label, flags|
      it "is forbidden to #{label}, even for their own jobs" do
        list(auth_headers_for(create(:user, **flags)))

        expect(response).to have_http_status(:forbidden)
      end
    end

    it "is forbidden to the member who requested a job" do
      list(auth_headers_for(requester))

      expect(response).to have_http_status(:forbidden)
    end

    it "401s without a token" do
      list({})

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "BotJob.enqueue!" do
    it "rejects an unknown kind" do
      expect { enqueue(kind: "nope") }.to raise_error(ActiveRecord::RecordInvalid)
    end

    it "requires a summary" do
      expect { enqueue(summary: " ") }.to raise_error(ActiveRecord::RecordInvalid)
      expect { BotJob.enqueue!(kind: "giveaway_hub_refresh") }.to raise_error(ArgumentError)
    end

    # Deploy window: the old release inserts jobs with no summary.
    it "accepts an insert without a summary and shows the kind in its place" do
      BotJob.connection.execute(<<~SQL.squish)
        INSERT INTO bot_jobs (kind, payload, created_at, updated_at)
        VALUES ('giveaway_hub_refresh', '{}', now(), now())
      SQL

      get "/api/v1/bot_jobs", headers: service_headers
      expect(json.fetch("data").sole).to include("kind" => "giveaway_hub_refresh", "summary" => "Giveaway hub refresh")
    end

    it "cuts a long summary to #{BotJob::SUMMARY_MAX} characters" do
      job = enqueue(summary: "Announce #{'x' * 300}")

      expect(job.summary.length).to eq(BotJob::SUMMARY_MAX)
      expect(job.summary).to start_with("Announce xxx").and end_with("...")
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
