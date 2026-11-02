# frozen_string_literal: true

require "rails_helper"

# Superadmin review of a Suggestion (web parity 2, #319): approve opens a
# GitHub issue in an allowlisted repo, reject records a reason, and both ask
# the bot to announce the outcome. Github::Client is stubbed at its
# constructor; its own spec stubs GitHub over HTTP.
RSpec.describe "api/v1/suggestions review behavior", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:client) { instance_double(Github::Client, configured?: true) }
  let(:superadmin) { create(:user) }
  let(:superadmin_headers) { auth_headers_for(superadmin, is_dev: true) }
  let(:suggestion) do
    create(:suggestion, title: "Dark mode", details: "Please", labels: "New Feature, Bug", created_by_name: "tester")
  end
  let(:issue_url) { "https://github.com/TheRPGClub/TheRPGClub-www/issues/42" }

  before do
    allow(Github::Client).to receive(:new).and_return(client)
    allow(client).to receive(:create_issue)
      .and_return(Github::Client::Issue.new(number: 42, url: issue_url, state: "open"))
  end

  def approve(id = suggestion.suggestion_id, data: { target_repo: "TheRPGClub/TheRPGClub-www" }, headers: superadmin_headers)
    post "/api/v1/suggestions/#{id}/approve", params: { data: data }, headers: headers, as: :json
  end

  def reject(id = suggestion.suggestion_id, data: { rejection_reason: "Out of scope" }, headers: superadmin_headers)
    post "/api/v1/suggestions/#{id}/reject", params: { data: data }, headers: headers, as: :json
  end

  describe "POST /api/v1/suggestions/:id/approve" do
    it "opens the GitHub issue the bot would, stores it and asks the bot to announce it" do
      freeze_time do
        expect { approve }.to change(BotJob, :count).by(1)

        expect(response).to have_http_status(:ok)
        expect(client).to have_received(:create_issue).with(
          repo: "TheRPGClub/TheRPGClub-www", title: "Dark mode", body: "tester: Please", labels: [ "New Feature", "Bug" ]
        )
        data = json.fetch("data")
        expect(data).to include(
          "suggestion_id" => suggestion.suggestion_id, "status" => "approved",
          "reviewed_by" => superadmin.user_id, "reviewed_at" => Time.current.utc.iso8601(3),
          "target_repo" => "TheRPGClub/TheRPGClub-www", "github_issue_number" => 42,
          "github_issue_url" => issue_url, "rejection_reason" => nil, "upvote_count" => 0
        )
        job = BotJob.last
        expect(json.dig("meta", "outcome_job_id")).to eq(job.id)
        expect(job.kind).to eq("suggestion_outcome")
        expect(job.requested_by_user_id).to eq(superadmin.user_id)
        expect(job.payload).to eq(
          "suggestion_id" => suggestion.suggestion_id, "outcome" => "approved",
          "created_by" => suggestion.created_by, "title" => "Dark mode",
          "github_issue_number" => 42, "github_issue_url" => issue_url, "rejection_reason" => nil
        )
      end
    end

    it "uses the bot's placeholders for a missing author name and details, and no labels" do
      bare = create(:suggestion, details: nil, labels: nil, created_by_name: nil)

      approve(bare.suggestion_id)

      expect(client).to have_received(:create_issue)
        .with(hash_including(body: "Unknown: No details provided.", labels: []))
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
      it "409s when the suggestion is #{status}, without calling GitHub" do
        suggestion.update!(status: status)

        expect { approve }.not_to change(BotJob, :count)

        expect(response).to have_http_status(:conflict)
        expect(json.fetch("error")).to include(status)
        expect(client).not_to have_received(:create_issue)
      end
    end

    it "502s and leaves the suggestion pending when GitHub fails" do
      allow(client).to receive(:create_issue).and_raise(Github::Client::RequestError, "GitHub returned HTTP 500")

      expect { approve }.not_to change(BotJob, :count)

      expect(response).to have_http_status(:bad_gateway)
      expect(json).to include("error" => "github_issue_failed", "message" => "GitHub returned HTTP 500")
      expect(suggestion.reload.status).to eq("pending")
    end

    it "503s when the GitHub App is not configured" do
      allow(client).to receive(:create_issue).and_raise(Github::Client::ConfigurationError, "Missing GitHub App config")

      approve

      expect(response).to have_http_status(:service_unavailable)
      expect(json.fetch("error")).to eq("github_not_configured")
      expect(suggestion.reload.status).to eq("pending")
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
      post "/api/v1/suggestions/#{suggestion.suggestion_id}/approve", headers: superadmin_headers, as: :json

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

  describe "POST /api/v1/suggestions/:id/reject" do
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
        expect(job.kind).to eq("suggestion_outcome")
        expect(job.payload).to eq(
          "suggestion_id" => suggestion.suggestion_id, "outcome" => "rejected",
          "created_by" => suggestion.created_by, "title" => "Dark mode",
          "github_issue_number" => nil, "github_issue_url" => nil, "rejection_reason" => "Out of scope"
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
      expect(suggestion.reload.status).to eq("pending")
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

    it "409s when the suggestion is not pending" do
      suggestion.update!(status: "withdrawn")

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

  describe "GitHub issue state on reads" do
    let(:viewer_headers) { auth_headers_for(create(:user)) }
    let!(:approved) do
      create(:suggestion, status: "approved", target_repo: "TheRPGClub/TheRPGClub-bot", github_issue_number: 5,
        github_issue_url: "https://github.com/TheRPGClub/TheRPGClub-bot/issues/5")
    end

    before do
      allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
      allow(client).to receive(:issue_state).and_return("closed")
    end

    def row_for(record)
      json.fetch("data").find { |row| row.fetch("suggestion_id") == record.suggestion_id }
    end

    it "adds the issue's state to approved suggestions, and null to the rest" do
      pending_one = create(:suggestion)

      get "/api/v1/suggestions", headers: viewer_headers

      expect(row_for(approved).fetch("github_issue_state")).to eq("closed")
      expect(row_for(pending_one).fetch("github_issue_state")).to be_nil
      expect(client).to have_received(:issue_state).once.with(repo: "TheRPGClub/TheRPGClub-bot", number: 5)
    end

    it "shows it on a single suggestion" do
      get "/api/v1/suggestions/#{approved.suggestion_id}", headers: viewer_headers

      expect(json.dig("data", "github_issue_state")).to eq("closed")
    end

    it "caches the state for about ten minutes" do
      get "/api/v1/suggestions", headers: viewer_headers
      get "/api/v1/suggestions/#{approved.suggestion_id}", headers: viewer_headers
      expect(client).to have_received(:issue_state).once

      travel 11.minutes do
        get "/api/v1/suggestions", headers: viewer_headers
      end
      expect(client).to have_received(:issue_state).twice
    end

    it "is null, and the read still succeeds, when GitHub fails" do
      allow(client).to receive(:issue_state).and_raise(Github::Client::RequestError, "GitHub returned HTTP 500")

      get "/api/v1/suggestions", headers: viewer_headers

      expect(response).to have_http_status(:ok)
      expect(row_for(approved).fetch("github_issue_state")).to be_nil
    end

    it "caches a failure for about ten minutes" do
      allow(client).to receive(:issue_state).and_raise(Github::Client::RequestError, "GitHub request failed: timeout")

      get "/api/v1/suggestions", headers: viewer_headers
      travel 9.minutes do
        get "/api/v1/suggestions", headers: viewer_headers
      end
      expect(client).to have_received(:issue_state).once

      travel 11.minutes do
        get "/api/v1/suggestions", headers: viewer_headers
      end
      expect(client).to have_received(:issue_state).twice
    end

    it "looks up issues with a short timeout" do
      get "/api/v1/suggestions", headers: viewer_headers

      expect(Github::Client).to have_received(:new).with(timeout: Github::IssueStateCache::LOOKUP_TIMEOUT_SECONDS)
      expect(Github::IssueStateCache::LOOKUP_TIMEOUT_SECONDS).to be <= 3
    end

    context "with many uncached approved suggestions" do
      let(:cap) { Github::IssueStateCache::MAX_LOOKUPS_PER_REQUEST }

      before do
        (cap + 6).times do |index|
          create(:suggestion, status: "approved", target_repo: "TheRPGClub/TheRPGClub-bot",
            github_issue_number: 100 + index)
        end
      end

      def states
        json.fetch("data").filter_map { |row| row["github_issue_state"] if row["status"] == "approved" }
      end

      it "makes at most the cap of GitHub calls per request, leaving the rest null for later views" do
        get "/api/v1/suggestions", params: { per: 500 }, headers: viewer_headers

        expect(response).to have_http_status(:ok)
        expect(client).to have_received(:issue_state).exactly(cap).times
        expect(states.size).to eq(cap)

        get "/api/v1/suggestions", params: { per: 500 }, headers: viewer_headers

        expect(client).to have_received(:issue_state).exactly(cap * 2).times
        expect(states.size).to eq(cap * 2)
      end

      it "stops looking up for the rest of the request after a GitHub failure" do
        allow(client).to receive(:issue_state).and_raise(Github::Client::RequestError, "GitHub request failed: timeout")

        get "/api/v1/suggestions", params: { per: 500 }, headers: viewer_headers

        expect(response).to have_http_status(:ok)
        expect(client).to have_received(:issue_state).once
      end
    end

    it "is null without calling GitHub when the GitHub App is not configured" do
      allow(client).to receive(:configured?).and_return(false)

      get "/api/v1/suggestions", headers: viewer_headers

      expect(row_for(approved).fetch("github_issue_state")).to be_nil
      expect(client).not_to have_received(:issue_state)
    end

    it "is null when the issue no longer exists" do
      allow(client).to receive(:issue_state).and_return(nil)

      get "/api/v1/suggestions", headers: viewer_headers

      expect(row_for(approved).fetch("github_issue_state")).to be_nil
    end
  end

  describe "DELETE /api/v1/suggestions/:id" do
    it "is gone: Suggestions are kept and reviewed through approve and reject" do
      delete "/api/v1/suggestions/#{suggestion.suggestion_id}", headers: service_headers

      expect(response).to have_http_status(:not_found)
      get "/api/v1/suggestions/#{suggestion.suggestion_id}", headers: service_headers
      expect(response).to have_http_status(:ok)
    end
  end
end
