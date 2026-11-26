# frozen_string_literal: true

require "rails_helper"

# Superadmin review of Feedback (web parity 2, #319; spec api#498): approve opens a
# GitHub issue in an allowlisted repo, reject records a reason, and both ask
# the bot to announce the outcome. Github::Client is stubbed at its
# constructor; its own spec stubs GitHub over HTTP.
RSpec.describe "api/v1/feedback review behavior", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:client) { instance_double(Github::Client, configured?: true) }
  let(:superadmin) { create(:user) }
  let(:superadmin_headers) { auth_headers_for(superadmin, is_dev: true) }
  let(:feedback) do
    create(:feedback, kind: "feature_request", title: "Dark mode", details: "Please", created_by_name: "tester")
  end
  let(:issue_url) { "https://github.com/TheRPGClub/TheRPGClub-www/issues/42" }

  before do
    allow(Github::Client).to receive(:new).and_return(client)
    allow(client).to receive(:create_issue)
      .and_return(Github::Client::Issue.new(number: 42, url: issue_url, state: "open"))
    allow(client).to receive(:find_issue_by_marker).and_return(nil)
  end

  def marker_for(record)
    "<!-- rpgclub-feedback:#{record.feedback_id} -->"
  end

  def approve(id = feedback.feedback_id, data: { target_repo: "TheRPGClub/TheRPGClub-www" }, headers: superadmin_headers)
    post "/api/v1/feedback/#{id}/approve", params: { data: data }, headers: headers, as: :json
  end

  def reject(id = feedback.feedback_id, data: { rejection_reason: "Out of scope" }, headers: superadmin_headers)
    post "/api/v1/feedback/#{id}/reject", params: { data: data }, headers: headers, as: :json
  end

  describe "POST /api/v1/feedback/:id/approve" do
    it "opens the GitHub issue the bot would, stores it and asks the bot to announce it" do
      freeze_time do
        expect { approve }.to change(BotJob, :count).by(1)

        expect(response).to have_http_status(:ok)
        expect(client).to have_received(:create_issue).with(
          repo: "TheRPGClub/TheRPGClub-www", title: "Dark mode", body: "tester: Please\n\n#{marker_for(feedback)}",
          labels: [ "enhancement" ]
        )
        expect(client).to have_received(:find_issue_by_marker).with(
          repo: "TheRPGClub/TheRPGClub-www", marker: marker_for(feedback), since: feedback.created_at
        )
        data = json.fetch("data")
        expect(data).to include(
          "feedback_id" => feedback.feedback_id, "status" => "approved",
          "reviewed_by" => superadmin.user_id, "reviewed_at" => Time.current.utc.iso8601(3),
          "target_repo" => "TheRPGClub/TheRPGClub-www", "github_issue_number" => 42,
          "github_issue_url" => issue_url, "rejection_reason" => nil, "upvote_count" => 0
        )
        job = BotJob.last
        expect(json.dig("meta", "outcome_job_id")).to eq(job.id)
        expect(job.kind).to eq("feedback_outcome")
        expect(job.summary).to eq('Announce that the Feature Request "Dark mode" was approved')
        expect(job.requested_by_user_id).to eq(superadmin.user_id)
        expect(job.payload).to eq(
          "feedback_id" => feedback.feedback_id, "kind" => "feature_request", "outcome" => "approved",
          "created_by" => feedback.created_by, "title" => "Dark mode",
          "github_issue_number" => 42, "github_issue_url" => issue_url, "rejection_reason" => nil,
          "feature_key" => "feedback"
        )
      end
    end

    it "uses the bot's placeholders for a missing author name and details" do
      bare = create(:feedback, details: nil, created_by_name: nil)

      approve(bare.feedback_id)

      expect(client).to have_received(:create_issue)
        .with(hash_including(body: "Unknown: No details provided.\n\n#{marker_for(bare)}"))
    end

    {
      "TheRPGClub/TheRPGClub-bot" => { "feature_request" => "new feature", "suggestion" => "improvement",
                                       "bug_report" => "bug" },
      "TheRPGClub/TheRPGClub-api" => { "feature_request" => "enhancement", "suggestion" => "enhancement",
                                       "bug_report" => "bug" },
      "TheRPGClub/TheRPGClub-www" => { "feature_request" => "enhancement", "suggestion" => "enhancement",
                                       "bug_report" => "bug" }
    }.each do |repo, labels|
      labels.each do |kind, label|
        it "labels a #{kind} issue in #{repo} #{label}" do
          record = create(:feedback, kind: kind)

          approve(record.feedback_id, data: { target_repo: repo })

          expect(client).to have_received(:create_issue).with(hash_including(repo: repo, labels: [ label ]))
        end
      end
    end

    it "lets the bot approve for a Discord reviewer, and still enqueues the announcement" do
      expect {
        approve(data: { target_repo: "TheRPGClub/TheRPGClub-bot", reviewed_by: "555" }, headers: service_headers)
      }.to change(BotJob, :count).by(1)

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("reviewed_by" => "555", "target_repo" => "TheRPGClub/TheRPGClub-bot")
      expect(BotJob.last.requested_by_user_id).to be_nil
    end

    it "ignores a member reviewer's body reviewed_by" do
      approve(data: { target_repo: "TheRPGClub/TheRPGClub-api", reviewed_by: "555" })

      expect(json.dig("data", "reviewed_by")).to eq(superadmin.user_id)
    end

    it "422s for a repo outside the allowlist without calling GitHub" do
      approve(data: { target_repo: "mfagerstrom/RPGClub_GameDB" })

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("error")).to include("TheRPGClub/TheRPGClub-bot")
      expect(client).not_to have_received(:create_issue)
    end

    it "422s without a target repo" do
      approve(data: { reviewed_by: "1" })

      expect(response).to have_http_status(:unprocessable_content)
    end

    %w[approved rejected withdrawn].each do |status|
      it "409s when feedback is #{status}, without calling GitHub" do
        feedback.update!(status: status)

        expect { approve }.not_to change(BotJob, :count)

        expect(response).to have_http_status(:conflict)
        expect(json.fetch("error")).to include(status)
        expect(client).not_to have_received(:create_issue)
      end
    end

    it "502s and leaves feedback pending when GitHub fails" do
      allow(client).to receive(:create_issue).and_raise(Github::Client::RequestError, "GitHub returned HTTP 500")

      expect { approve }.not_to change(BotJob, :count)

      expect(response).to have_http_status(:bad_gateway)
      expect(json).to include("error" => "github_issue_failed", "message" => "GitHub returned HTTP 500")
      expect(feedback.reload.status).to eq("pending")
    end

    it "reuses an issue an earlier approval opened but whose response was lost, instead of a duplicate" do
      found = Github::Client::Issue.new(number: 41, url: "https://github.com/TheRPGClub/TheRPGClub-www/issues/41",
        state: "open")
      allow(client).to receive(:find_issue_by_marker).and_return(found)

      approve

      expect(response).to have_http_status(:ok)
      expect(client).not_to have_received(:create_issue)
      expect(json.fetch("data")).to include("status" => "approved", "github_issue_number" => 41,
        "github_issue_url" => found.url)
    end

    it "does not hold a transaction (or the row lock) across the GitHub calls" do
      baseline = ActiveRecord::Base.connection.open_transactions
      during = []
      allow(client).to receive(:find_issue_by_marker) { during << ActiveRecord::Base.connection.open_transactions; nil }
      allow(client).to receive(:create_issue) do
        during << ActiveRecord::Base.connection.open_transactions
        Github::Client::Issue.new(number: 42, url: issue_url, state: "open")
      end

      approve

      expect(response).to have_http_status(:ok)
      expect(during).to eq([ baseline, baseline ])
    end

    it "409s while another approval of the same feedback is in progress, without calling GitHub" do
      feedback.update_column(:approval_started_at, 10.seconds.ago)

      expect { approve }.not_to change(BotJob, :count)

      expect(response).to have_http_status(:conflict)
      expect(json.fetch("error")).to eq("approval_in_progress")
      expect(client).not_to have_received(:create_issue)
      expect(client).not_to have_received(:find_issue_by_marker)
    end

    it "takes over an approval mark left by a request that died" do
      feedback.update_column(:approval_started_at, 10.minutes.ago)

      approve

      expect(response).to have_http_status(:ok)
      expect(feedback.reload.status).to eq("approved")
    end

    it "can be retried at once after a GitHub failure" do
      allow(client).to receive(:create_issue).and_raise(Github::Client::RequestError, "GitHub request failed: timeout")
      approve
      expect(response).to have_http_status(:bad_gateway)

      allow(client).to receive(:create_issue)
        .and_return(Github::Client::Issue.new(number: 42, url: issue_url, state: "open"))
      approve

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "github_issue_number")).to eq(42)
    end

    it "409s, and announces nothing, when feedback stopped being pending during the GitHub call" do
      allow(client).to receive(:create_issue) do
        RpgClubFeedback.where(feedback_id: feedback.feedback_id).update_all(status: "withdrawn")
        Github::Client::Issue.new(number: 42, url: issue_url, state: "open")
      end

      expect { approve }.not_to change(BotJob, :count)

      expect(response).to have_http_status(:conflict)
      expect(feedback.reload).to have_attributes(status: "withdrawn", github_issue_number: nil)
    end

    it "502s when the lookup for an earlier issue fails" do
      allow(client).to receive(:find_issue_by_marker).and_raise(Github::Client::RequestError, "GitHub returned HTTP 502")

      approve

      expect(response).to have_http_status(:bad_gateway)
      expect(client).not_to have_received(:create_issue)
      expect(feedback.reload.status).to eq("pending")
    end

    it "does not show its approval bookkeeping" do
      approve

      expect(json.fetch("data")).not_to have_key("approval_started_at")
    end

    it "503s when the GitHub App is not configured" do
      allow(client).to receive(:create_issue).and_raise(Github::Client::ConfigurationError, "Missing GitHub App config")

      approve

      expect(response).to have_http_status(:service_unavailable)
      expect(json.fetch("error")).to eq("github_not_configured")
      expect(feedback.reload.status).to eq("pending")
    end

    it "refuses an Admin who is not a Superadmin" do
      approve(headers: auth_headers_for(create(:user, role_admin: true)))

      expect(response).to have_http_status(:forbidden)
      expect(client).not_to have_received(:create_issue)
    end

    it "refuses a member" do
      approve(headers: auth_headers_for(create(:user, role_member: true)))

      expect(response).to have_http_status(:forbidden)
    end

    it "400s without the data envelope" do
      post "/api/v1/feedback/#{feedback.feedback_id}/approve", headers: superadmin_headers, as: :json

      expect(response).to have_http_status(:bad_request)
    end

    it "404s for an unknown id" do
      approve(999_999_999)

      expect(response).to have_http_status(:not_found)
    end

    it "requires authentication" do
      approve(headers: {})

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "POST /api/v1/feedback/:id/reject" do
    it "records the reason and asks the bot to announce it" do
      freeze_time do
        expect { reject }.to change(BotJob, :count).by(1)

        expect(response).to have_http_status(:ok)
        expect(json.fetch("data")).to include(
          "status" => "rejected", "rejection_reason" => "Out of scope", "reviewed_by" => superadmin.user_id,
          "reviewed_at" => Time.current.utc.iso8601(3), "github_issue_number" => nil, "target_repo" => nil
        )
        job = BotJob.last
        expect(json.dig("meta", "outcome_job_id")).to eq(job.id)
        expect(job.kind).to eq("feedback_outcome")
        expect(job.summary).to eq('Announce that the Feature Request "Dark mode" was rejected')
        expect(job.payload).to eq(
          "feedback_id" => feedback.feedback_id, "kind" => "feature_request", "outcome" => "rejected",
          "created_by" => feedback.created_by, "title" => "Dark mode",
          "github_issue_number" => nil, "github_issue_url" => nil, "rejection_reason" => "Out of scope",
          "feature_key" => "feedback"
        )
        expect(client).not_to have_received(:create_issue)
      end
    end

    it "trims the reason" do
      reject(data: { rejection_reason: "  Duplicate \n" })

      expect(json.dig("data", "rejection_reason")).to eq("Duplicate")
    end

    it "422s for a blank reason" do
      expect { reject(data: { rejection_reason: "   " }) }.not_to change(BotJob, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(feedback.reload.status).to eq("pending")
    end

    it "422s for a reason over 2000 characters" do
      reject(data: { rejection_reason: "x" * 2001 })

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "lets the bot reject for a Discord reviewer" do
      reject(data: { rejection_reason: "No", reviewed_by: "555" }, headers: service_headers)

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "reviewed_by")).to eq("555")
    end

    it "409s when feedback is not pending" do
      feedback.update!(status: "withdrawn")

      reject

      expect(response).to have_http_status(:conflict)
    end

    it "refuses an Admin who is not a Superadmin" do
      reject(headers: auth_headers_for(create(:user, role_admin: true)))

      expect(response).to have_http_status(:forbidden)
    end

    it "requires authentication" do
      reject(headers: {})

      expect(response).to have_http_status(:unauthorized)
    end
  end

  # Reads never call GitHub: they read the cached states (one cache read per
  # page), and a missing or stale state queues Github::IssueStateRefreshJob,
  # which fills the cache for later reads. A stale state keeps being shown
  # while it refreshes.
  describe "GitHub issue state on reads" do
    include ActiveJob::TestHelper

    let(:viewer_headers) { auth_headers_for(create(:user)) }
    let(:cache) { ActiveSupport::Cache::MemoryStore.new }
    let!(:approved) do
      create(:feedback, status: "approved", target_repo: "TheRPGClub/TheRPGClub-bot", github_issue_number: 5,
        github_issue_url: "https://github.com/TheRPGClub/TheRPGClub-bot/issues/5")
    end

    before do
      allow(Rails).to receive(:cache).and_return(cache)
      allow(client).to receive(:issue_state).and_return("closed")
    end

    def row_for(record)
      json.fetch("data").find { |row| row.fetch("feedback_id") == record.feedback_id }
    end

    def board(**params)
      get "/api/v1/feedback", params: params, headers: viewer_headers
    end

    it "never calls GitHub during a read; a refresh job fills the state for the next one" do
      pending_one = create(:feedback)

      board
      expect(client).not_to have_received(:issue_state)
      expect(row_for(approved).fetch("github_issue_state")).to be_nil
      expect(Github::IssueStateRefreshJob).to have_been_enqueued.with([ [ "TheRPGClub/TheRPGClub-bot", 5 ] ])

      perform_enqueued_jobs
      board

      expect(row_for(approved).fetch("github_issue_state")).to eq("closed")
      expect(row_for(pending_one).fetch("github_issue_state")).to be_nil
      expect(client).to have_received(:issue_state).once.with(repo: "TheRPGClub/TheRPGClub-bot", number: 5)
    end

    it "shows it on a single feedback" do
      Github::IssueStateCache.store("TheRPGClub/TheRPGClub-bot", 5, "closed")

      get "/api/v1/feedback/#{approved.feedback_id}", headers: viewer_headers

      expect(json.dig("data", "github_issue_state")).to eq("closed")
    end

    it "reads every state on the page in one cache read" do
      3.times { |i| create(:feedback, status: "approved", target_repo: "TheRPGClub/TheRPGClub-bot", github_issue_number: 50 + i) }
      allow(cache).to receive(:read_multi).and_call_original
      allow(cache).to receive(:read).and_call_original

      board

      expect(cache).to have_received(:read_multi).once
      expect(cache).not_to have_received(:read).with(/github_issue_state/)
    end

    it "queues no refresh while every state is fresh" do
      Github::IssueStateCache.store("TheRPGClub/TheRPGClub-bot", 5, "open")

      board

      expect(row_for(approved).fetch("github_issue_state")).to eq("open")
      expect(Github::IssueStateRefreshJob).not_to have_been_enqueued
    end

    it "keeps showing a stale state while it refreshes after about ten minutes" do
      Github::IssueStateCache.store("TheRPGClub/TheRPGClub-bot", 5, "open")

      travel 11.minutes do
        board
        expect(row_for(approved).fetch("github_issue_state")).to eq("open")
        expect(Github::IssueStateRefreshJob).to have_been_enqueued

        perform_enqueued_jobs
        board
        expect(row_for(approved).fetch("github_issue_state")).to eq("closed")
      end
    end

    describe "the refresh job" do
      let(:pairs) { [ [ "TheRPGClub/TheRPGClub-bot", 5 ] ] }

      it "looks up issues with a short timeout" do
        Github::IssueStateRefreshJob.perform_now(pairs)

        expect(Github::Client).to have_received(:new).with(timeout: Github::IssueStateCache::LOOKUP_TIMEOUT_SECONDS)
        expect(Github::IssueStateCache::LOOKUP_TIMEOUT_SECONDS).to be <= 3
      end

      it "skips states another refresh already filled" do
        Github::IssueStateCache.store(*pairs.first, "open")

        Github::IssueStateRefreshJob.perform_now(pairs)

        expect(client).not_to have_received(:issue_state)
      end

      it "caches a failure as null for about ten minutes, and the read still succeeds" do
        allow(client).to receive(:issue_state).and_raise(Github::Client::RequestError, "GitHub returned HTTP 500")

        Github::IssueStateRefreshJob.perform_now(pairs)
        board

        expect(response).to have_http_status(:ok)
        expect(row_for(approved).fetch("github_issue_state")).to be_nil
        travel(9.minutes) { board }
        expect(Github::IssueStateRefreshJob).not_to have_been_enqueued
        travel(11.minutes) { board }
        expect(Github::IssueStateRefreshJob).to have_been_enqueued
      end

      it "stops at the first GitHub failure, leaving the rest for a later refresh" do
        allow(client).to receive(:issue_state).and_raise(Github::Client::RequestError, "GitHub request failed: timeout")
        many = 4.times.map { |i| [ "TheRPGClub/TheRPGClub-bot", 100 + i ] }

        Github::IssueStateRefreshJob.perform_now(many)

        expect(client).to have_received(:issue_state).once
      end

      it "calls nothing when the GitHub App is not configured" do
        allow(client).to receive(:configured?).and_return(false)

        Github::IssueStateRefreshJob.perform_now(pairs)
        board

        expect(client).not_to have_received(:issue_state)
        expect(row_for(approved).fetch("github_issue_state")).to be_nil
      end

      describe "Done" do
        let(:done_jobs) { BotJob.where(kind: "feedback_outcome").select { |job| job.payload["outcome"] == "done" } }

        it "makes Approved Feedback Done and queues exactly one Done notice when it sees the issue closed" do
          Github::IssueStateRefreshJob.perform_now(pairs)
          travel(11.minutes) { Github::IssueStateRefreshJob.perform_now(pairs) }

          expect(approved.reload).to be_done
          expect(done_jobs.size).to eq(1)
          expect(done_jobs.first.payload).to include(
            "feedback_id" => approved.feedback_id, "kind" => approved.kind, "outcome" => "done",
            "created_by" => approved.created_by, "title" => approved.title, "github_issue_number" => 5,
            "github_issue_url" => approved.github_issue_url, "feature_key" => "feedback"
          )
          board
          expect(row_for(approved)).to include("done" => true, "github_issue_state" => "closed")
        end

        it "moves reopened Feedback back to Open without a notice, and sends none when it closes again" do
          Github::IssueStateRefreshJob.perform_now(pairs)
          allow(client).to receive(:issue_state).and_return("open")
          travel(11.minutes) { Github::IssueStateRefreshJob.perform_now(pairs) }

          expect(approved.reload).not_to be_done
          expect(approved).to be_upvotable

          allow(client).to receive(:issue_state).and_return("closed")
          travel(22.minutes) { Github::IssueStateRefreshJob.perform_now(pairs) }

          expect(approved.reload).to be_done
          expect(done_jobs.size).to eq(1)
        end

        it "sends nothing while the issue is open, or for Feedback that is not Approved" do
          allow(client).to receive(:issue_state).and_return("open")
          Github::IssueStateRefreshJob.perform_now(pairs)
          expect(approved.reload).not_to be_done

          rejected = create(:feedback, status: "rejected", rejection_reason: "No",
            target_repo: "TheRPGClub/TheRPGClub-bot", github_issue_number: 6)
          allow(client).to receive(:issue_state).and_return("closed")
          Github::IssueStateRefreshJob.perform_now([ [ "TheRPGClub/TheRPGClub-bot", 6 ] ])

          expect(rejected.reload.done_at).to be_nil
          expect(done_jobs).to be_empty
        end

        it "changes nothing when the lookup fails" do
          allow(client).to receive(:issue_state).and_raise(Github::Client::RequestError, "boom")

          Github::IssueStateRefreshJob.perform_now(pairs)

          expect(approved.reload).not_to be_done
          expect(done_jobs).to be_empty
        end
      end

      it "leaves the state null when the issue no longer exists" do
        allow(client).to receive(:issue_state).and_return(nil)

        Github::IssueStateRefreshJob.perform_now(pairs)
        board

        expect(row_for(approved).fetch("github_issue_state")).to be_nil
      end
    end
  end

  describe "DELETE /api/v1/feedback/:id" do
    it "is gone: Feedback are kept and reviewed through approve and reject" do
      delete "/api/v1/feedback/#{feedback.feedback_id}", headers: service_headers

      expect(response).to have_http_status(:not_found)
      get "/api/v1/feedback/#{feedback.feedback_id}", headers: service_headers
      expect(response).to have_http_status(:ok)
    end
  end
end
