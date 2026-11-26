# frozen_string_literal: true

require "rails_helper"

# Behavior specs for the Feedback Board endpoints. Review (approve, reject)
# is in feedback_reviews_spec.rb.
RSpec.describe "api/v1/feedback behavior", type: :request do
  describe "GET /api/v1/feedback" do
    it "lists feedback (newest first when none are upvoted) with the documented fields" do
      older = create(:feedback, kind: "bug_report")
      newer = create(:feedback)
      older.update_column(:created_at, 2.hours.ago)
      newer.update_column(:created_at, 1.hour.ago)

      get "/api/v1/feedback", params: { per: 500 }, headers: auth_headers_for(create(:user))

      expect(response).to have_http_status(:ok)
      ids = json.fetch("data").map { |s| s.fetch("feedback_id") }
      expect(ids.index(newer.feedback_id)).to be < ids.index(older.feedback_id)
      row = json.fetch("data").find { |s| s.fetch("feedback_id") == older.feedback_id }
      expect(row).to include(
        "title" => older.title,
        "details" => older.details,
        "kind" => "bug_report",
        "created_by" => older.created_by,
        "created_by_name" => older.created_by_name
      )
      expect(json.fetch("meta")).to include("page" => 1)
    end

    it "returns a new feedback as pending with empty review fields" do
      feedback = create(:feedback)

      get "/api/v1/feedback", headers: auth_headers_for(create(:user))

      row = json.fetch("data").find { |s| s.fetch("feedback_id") == feedback.feedback_id }
      expect(row).to include(
        "status" => "pending", "reviewed_by" => nil, "reviewed_at" => nil, "rejection_reason" => nil,
        "target_repo" => nil, "github_issue_number" => nil, "github_issue_url" => nil
      )
    end

    it "filters by one or more comma-separated statuses" do
      pending_one = create(:feedback)
      approved = create(:feedback, status: "approved")
      rejected = create(:feedback, status: "rejected", rejection_reason: "No")
      withdrawn = create(:feedback, status: "withdrawn")
      headers = auth_headers_for(create(:user))

      get "/api/v1/feedback", params: { status: "pending,approved" }, headers: headers
      ids = json.fetch("data").map { |s| s.fetch("feedback_id") }
      expect(ids).to contain_exactly(pending_one.feedback_id, approved.feedback_id)
      expect(json.dig("meta", "count")).to eq(2)

      get "/api/v1/feedback", params: { status: "rejected" }, headers: headers
      expect(json.fetch("data").map { |s| s.fetch("feedback_id") }).to eq([ rejected.feedback_id ])

      get "/api/v1/feedback", headers: headers
      expect(json.fetch("data").map { |s| s.fetch("feedback_id") })
        .to include(pending_one.feedback_id, withdrawn.feedback_id)
    end

    describe "kind tabs with the Open / Closed filter" do
      let(:headers) { auth_headers_for(create(:user)) }
      let!(:original) { create(:feedback, kind: "bug_report") }
      let!(:pending_bug) { original }
      let!(:approved_bug) { create(:feedback, kind: "bug_report", status: "approved") }
      let!(:done_bug) { create(:feedback, kind: "bug_report", status: "approved", done_at: 1.hour.ago) }
      let!(:rejected_bug) { create(:feedback, kind: "bug_report", status: "rejected", rejection_reason: "No") }
      let!(:duplicate_bug) { create(:feedback, kind: "bug_report", status: "duplicate", duplicate_of: original) }
      let!(:withdrawn_bug) { create(:feedback, kind: "bug_report", status: "withdrawn") }
      let!(:pending_idea) { create(:feedback, kind: "feature_request") }

      def ids = json.fetch("data").map { |row| row.fetch("feedback_id") }

      it "lists one kind's Open Feedback, Done included and marked Done" do
        get "/api/v1/feedback", params: { kind: "bug_report", status: "open" }, headers: headers

        expect(response).to have_http_status(:ok)
        expect(ids).to contain_exactly(pending_bug.feedback_id, approved_bug.feedback_id, done_bug.feedback_id)
        done_flags = json.fetch("data").to_h { |row| [ row.fetch("feedback_id"), row.fetch("done") ] }
        expect(done_flags).to eq(pending_bug.feedback_id => false, approved_bug.feedback_id => false,
          done_bug.feedback_id => true)
        expect(json.dig("meta", "count")).to eq(3)
      end

      it "lists one kind's Closed Feedback: Rejected, Duplicate and Withdrawn" do
        get "/api/v1/feedback", params: { kind: "bug_report", status: "closed" }, headers: headers

        expect(ids).to contain_exactly(rejected_bug.feedback_id, duplicate_bug.feedback_id, withdrawn_bug.feedback_id)
      end

      it "lists only Done Feedback with status=done" do
        get "/api/v1/feedback", params: { kind: "bug_report", status: "done" }, headers: headers

        expect(ids).to eq([ done_bug.feedback_id ])
      end

      it "counts every kind's Open, Closed and Done Feedback, whatever the filters" do
        get "/api/v1/feedback", params: { kind: "bug_report", status: "closed" }, headers: headers

        expect(json.dig("meta", "totals")).to eq(
          "bug_report" => { "open" => 3, "closed" => 3, "done" => 1 },
          "feature_request" => { "open" => 1, "closed" => 0, "done" => 0 },
          "suggestion" => { "open" => 0, "closed" => 0, "done" => 0 }
        )
      end

      it "400s for an unknown kind" do
        get "/api/v1/feedback", params: { kind: "bug_report,idea" }, headers: headers

        expect(response).to have_http_status(:bad_request)
        expect(json.fetch("error")).to include("idea")
      end
    end

    it "400s for an unknown status" do
      get "/api/v1/feedback", params: { status: "pending,bogus" }, headers: auth_headers_for(create(:user))

      expect(response).to have_http_status(:bad_request)
      expect(json.fetch("error")).to include("bogus")
    end

    it "sorts by upvotes, then newest first, with the count and whether the viewer upvoted" do
      viewer = create(:user)
      quiet_old = create(:feedback)
      quiet_new = create(:feedback)
      popular = create(:feedback)
      liked = create(:feedback)
      quiet_old.update_column(:created_at, 3.days.ago)
      quiet_new.update_column(:created_at, 1.day.ago)
      2.times { create(:feedback_upvote, feedback: popular) }
      create(:feedback_upvote, feedback: liked, user: viewer)

      get "/api/v1/feedback", params: { per: 500 }, headers: auth_headers_for(viewer)

      rows = json.fetch("data")
      expect(rows.map { |r| r.fetch("feedback_id") }).to eq(
        [ popular, liked, quiet_new, quiet_old ].map(&:feedback_id)
      )
      expect(rows.map { |r| [ r.fetch("upvote_count"), r.fetch("viewer_upvoted") ] })
        .to eq([ [ 2, false ], [ 1, true ], [ 0, false ], [ 0, false ] ])
      expect(json.dig("meta", "count")).to eq(4)
    end

    it "groups the board Approved (not Done), Pending, Done, then closed, most upvoted first within each" do
      viewer = create(:user)
      approved_quiet = create(:feedback, status: "approved")
      approved_liked = create(:feedback, status: "approved")
      pending_old = create(:feedback)
      pending_new = create(:feedback)
      pending_liked = create(:feedback)
      done_liked = create(:feedback, status: "approved", done_at: 1.hour.ago)
      done_quiet = create(:feedback, status: "approved", done_at: 2.hours.ago)
      rejected_liked = create(:feedback, status: "rejected", rejection_reason: "No")
      withdrawn = create(:feedback, status: "withdrawn")
      pending_old.update_column(:created_at, 3.days.ago)
      pending_new.update_column(:created_at, 1.day.ago)
      # Upvotes added before closing/finishing (frozen afterwards) still count.
      3.times { create(:feedback_upvote, feedback: pending_liked) }
      3.times { create(:feedback_upvote, feedback: done_liked) }
      5.times { create(:feedback_upvote, feedback: rejected_liked) }
      create(:feedback_upvote, feedback: approved_liked)
      withdrawn.update_column(:created_at, 1.minute.from_now)

      get "/api/v1/feedback", params: { per: 500 }, headers: auth_headers_for(viewer)
      all_ids = json.fetch("data").map { |r| r.fetch("feedback_id") }

      expect(all_ids).to eq(
        [ approved_liked, approved_quiet, pending_liked, pending_new, pending_old, done_liked, done_quiet,
          rejected_liked, withdrawn ].map(&:feedback_id)
      )

      get "/api/v1/feedback", params: { status: "open", per: 500 }, headers: auth_headers_for(viewer)
      expect(json.fetch("data").map { |r| r.fetch("feedback_id") }).to eq(
        [ approved_liked, approved_quiet, pending_liked, pending_new, pending_old, done_liked, done_quiet ]
          .map(&:feedback_id)
      )
    end

    it "pages the sorted list" do
      top = create(:feedback)
      create(:feedback_upvote, feedback: top)
      create(:feedback)

      get "/api/v1/feedback", params: { per: 1, page: 1 }, headers: auth_headers_for(create(:user))

      expect(json.fetch("data").map { |r| r.fetch("feedback_id") }).to eq([ top.feedback_id ])
      expect(json.fetch("meta")).to include("count" => 2, "pages" => 2)
    end

    describe "sort=recent" do
      let(:viewer) { create(:user) }

      # Created `created` ago and last changed `changed` ago (default: never since).
      def feedback_at(created, changed = created, **attrs)
        create(:feedback, **attrs).tap do |s|
          s.update_columns(created_at: created.ago, updated_at: changed.ago)
        end
      end

      it "lists the latest activity first: new Feedback, a review or an upvote" do
        quiet = feedback_at(5.days)
        created = feedback_at(2.days)
        reviewed = feedback_at(6.days, 1.day, status: "rejected", rejection_reason: "No")
        upvoted = feedback_at(7.days)
        create(:feedback_upvote, feedback: upvoted).update_column(:created_at, 3.hours.ago)
        popular = feedback_at(4.days)
        3.times { create(:feedback_upvote, feedback: popular).update_column(:created_at, 4.days.ago) }

        get "/api/v1/feedback", params: { sort: "recent", per: 500 }, headers: auth_headers_for(viewer)

        expect(response).to have_http_status(:ok)
        rows = json.fetch("data")
        expect(rows.map { |r| r.fetch("feedback_id") })
          .to eq([ upvoted, reviewed, created, popular, quiet ].map(&:feedback_id))
        expect(Time.zone.parse(rows.first.fetch("last_activity_at"))).to be_within(1.second).of(3.hours.ago)
        expect(Time.zone.parse(rows.second.fetch("last_activity_at"))).to be_within(1.second).of(1.day.ago)
      end

      it "combines with the status filter and pages" do
        older = feedback_at(2.days)
        newer = feedback_at(1.day)
        feedback_at(1.hour, status: "withdrawn")

        get "/api/v1/feedback", params: { sort: "recent", status: "pending", per: 1 },
          headers: auth_headers_for(viewer)

        expect(json.fetch("data").map { |r| r.fetch("feedback_id") }).to eq([ newer.feedback_id ])
        expect(json.fetch("meta")).to include("count" => 2, "pages" => 2)
        expect(older.feedback_id).to be < newer.feedback_id
      end

      it "422s with invalid_sort on an unknown sort" do
        get "/api/v1/feedback", params: { sort: "bogus" }, headers: auth_headers_for(viewer)

        expect(response).to have_http_status(:unprocessable_content)
        expect(json).to include("error" => "invalid_sort")
        expect(json.fetch("message")).to include("board", "recent")
      end
    end

    it "requires authentication" do
      get "/api/v1/feedback"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/feedback/:id" do
    it "shows feedback" do
      feedback = create(:feedback)

      get "/api/v1/feedback/#{feedback.feedback_id}", headers: auth_headers_for(create(:user))

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include(
        "feedback_id" => feedback.feedback_id,
        "title" => feedback.title,
        "upvote_count" => 0,
        "viewer_upvoted" => false
      )
    end

    it "404s for an unknown id" do
      get "/api/v1/feedback/999999999", headers: service_headers

      expect(response).to have_http_status(:not_found)
      expect(json).to have_key("error")
    end
  end

  describe "POST /api/v1/feedback" do
    let(:payload) do
      { data: { kind: "feature_request", title: "Add dark mode", details: "Please", created_by: "77",
                created_by_name: "tester" } }
    end

    it "creates feedback for the bot" do
      expect {
        post "/api/v1/feedback", params: payload, headers: service_headers, as: :json
      }.to change(RpgClubFeedback, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(json.fetch("data")).to include(
        "kind" => "feature_request",
        "title" => "Add dark mode",
        "details" => "Please",
        "created_by" => "77",
        "created_by_name" => "tester"
      )
    end

    it "lets a Members role holder create one as its author and asks the bot to ping the bot dev" do
      member = create(:user, username: "suggester", role_member: true)
      forged = { data: { kind: "bug_report", title: "Dark mode", details: "Please", where: "website", what_happened: "Light",
                         expected: "Dark", created_by: "999", created_by_name: "someone else" } }

      expect {
        post "/api/v1/feedback", params: forged, headers: auth_headers_for(member), as: :json
      }.to change(RpgClubFeedback, :count).by(1).and change(BotJob, :count).by(1)

      expect(response).to have_http_status(:created)
      data = json.fetch("data")
      expect(data).to include("kind" => "bug_report", "title" => "Dark mode", "status" => "pending",
        "created_by" => member.user_id, "created_by_name" => "suggester")
      job = BotJob.last
      expect(job.kind).to eq("feedback_submitted")
      expect(job.summary).to eq('Announce the new Bug Report "Dark mode"')
      expect(job.payload).to eq("feedback_id" => data.fetch("feedback_id"), "kind" => "bug_report",
        "created_by" => member.user_id, "feature_key" => "feedback")
      expect(job.requested_by_user_id).to eq(member.user_id)
    end

    it "refuses a signed-in user without the Members role" do
      post "/api/v1/feedback", params: payload, headers: auth_headers_for(create(:user)), as: :json

      expect(response).to have_http_status(:forbidden)
    end

    it "lets a Moderator without the Members role create one" do
      moderator = create(:user, role_moderator: true)

      post "/api/v1/feedback", params: payload, headers: auth_headers_for(moderator), as: :json

      expect(response).to have_http_status(:created)
      expect(json.dig("data", "created_by")).to eq(moderator.user_id)
    end

    it "does not enqueue a ping for the bot's own submissions (the bot pings inline)" do
      expect {
        post "/api/v1/feedback", params: payload, headers: service_headers, as: :json
      }.not_to change(BotJob, :count)
    end

    it "ignores status and review fields in the body" do
      body = { data: { kind: "suggestion", title: "Sneaky", status: "approved", reviewed_by: "1", github_issue_number: 5 } }

      post "/api/v1/feedback", params: body, headers: auth_headers_for(create(:user, role_member: true)), as: :json

      expect(response).to have_http_status(:created)
      expect(json.fetch("data")).to include("status" => "pending", "reviewed_by" => nil, "github_issue_number" => nil)
    end

    it "leaves no ping job when the create fails" do
      expect {
        post "/api/v1/feedback", params: { data: { kind: "suggestion", title: "" } }, headers: auth_headers_for(create(:user, role_member: true)), as: :json
      }.not_to change(BotJob, :count)

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "allows the service" do
      post "/api/v1/feedback", params: payload, headers: service_headers, as: :json

      expect(response).to have_http_status(:created)
    end

    it "422s when title is missing" do
      post "/api/v1/feedback", params: { data: { kind: "suggestion", details: "no title" } }, headers: service_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "422s when title exceeds the column limit" do
      post "/api/v1/feedback", params: { data: { kind: "suggestion", title: "x" * 201 } }, headers: service_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "422s when kind is missing" do
      post "/api/v1/feedback", params: { data: { title: "No kind" } }, headers: service_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "422s for an unknown kind, including the old labels" do
      post "/api/v1/feedback", params: { data: { kind: "Bug", title: "Old label" } }, headers: service_headers,
        as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "takes each kind" do
      RpgClubFeedback::KINDS.each do |kind|
        bug = kind == "bug_report" ? { where: "bot", what_happened: "It broke", expected: "It works" } : {}
        post "/api/v1/feedback", params: { data: { kind: kind, title: "A #{kind}", **bug } }, headers: service_headers,
          as: :json

        expect(response).to have_http_status(:created)
        expect(json.dig("data", "kind")).to eq(kind)
      end
    end

    it "ignores labels in the body" do
      post "/api/v1/feedback", params: { data: { kind: "suggestion", title: "T", labels: "Bug" } },
        headers: service_headers, as: :json

      expect(response).to have_http_status(:created)
      expect(json.fetch("data")).not_to have_key("labels")
    end

    it "400s when the data envelope is missing" do
      post "/api/v1/feedback", params: { title: "bare" }, headers: service_headers, as: :json

      expect(response).to have_http_status(:bad_request)
    end

    it "requires authentication" do
      post "/api/v1/feedback", params: payload, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "POST /api/v1/feedback/:id/withdraw" do
    let(:author) { create(:user) }
    let(:feedback) { create(:feedback, created_by: author.user_id) }

    it "lets the author withdraw pending feedback" do
      post "/api/v1/feedback/#{feedback.feedback_id}/withdraw", headers: auth_headers_for(author)

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("feedback_id" => feedback.feedback_id, "status" => "withdrawn")
      get "/api/v1/feedback/#{feedback.feedback_id}", headers: auth_headers_for(author)
      expect(json.dig("data", "status")).to eq("withdrawn")
    end

    it "refuses another member" do
      post "/api/v1/feedback/#{feedback.feedback_id}/withdraw", headers: auth_headers_for(create(:user))

      expect(response).to have_http_status(:forbidden)
    end

    it "refuses staff who are not the author" do
      admin = create(:user, role_admin: true)

      post "/api/v1/feedback/#{feedback.feedback_id}/withdraw", headers: auth_headers_for(admin, is_dev: true)

      expect(response).to have_http_status(:forbidden)
    end

    it "refuses the service, which has no author identity" do
      post "/api/v1/feedback/#{feedback.feedback_id}/withdraw", headers: service_headers

      expect(response).to have_http_status(:forbidden)
    end

    %w[approved rejected withdrawn].each do |status|
      it "409s when feedback is #{status}" do
        feedback.update!(status: status)

        post "/api/v1/feedback/#{feedback.feedback_id}/withdraw", headers: auth_headers_for(author)

        expect(response).to have_http_status(:conflict)
        expect(json.fetch("error")).to include(status)
      end
    end

    it "404s for an unknown id" do
      post "/api/v1/feedback/999999999/withdraw", headers: auth_headers_for(author)

      expect(response).to have_http_status(:not_found)
    end

    it "requires authentication" do
      post "/api/v1/feedback/#{feedback.feedback_id}/withdraw"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "POST /api/v1/feedback/:id/upvote" do
    let(:member) { create(:user, role_member: true) }
    let(:feedback) { create(:feedback) }

    it "records one upvote per member and returns the updated count" do
      create(:feedback_upvote, feedback: feedback)

      2.times { post "/api/v1/feedback/#{feedback.feedback_id}/upvote", headers: auth_headers_for(member) }

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("feedback_id" => feedback.feedback_id,
        "upvote_count" => 2, "viewer_upvoted" => true)
    end

    it "re-checks under the row lock, refusing Feedback closed after it was read" do
      allow(RpgClubFeedback).to receive(:find).and_wrap_original do |original, *args|
        original.call(*args).tap do |record|
          RpgClubFeedback.where(feedback_id: record.feedback_id).update_all(status: "rejected")
        end
      end

      post "/api/v1/feedback/#{feedback.feedback_id}/upvote", headers: auth_headers_for(member)

      expect(response).to have_http_status(:conflict)
      expect(feedback.upvotes.count).to eq(0)
    end

    it "accepts upvotes on approved feedback" do
      feedback.update!(status: "approved")

      post "/api/v1/feedback/#{feedback.feedback_id}/upvote", headers: auth_headers_for(member)

      expect(response).to have_http_status(:ok)
    end

    %w[rejected withdrawn].each do |status|
      it "409s on #{status} feedback" do
        feedback.update!(status: status)

        post "/api/v1/feedback/#{feedback.feedback_id}/upvote", headers: auth_headers_for(member)

        expect(response).to have_http_status(:conflict)
      end
    end

    it "409s on a Duplicate" do
      feedback.update!(status: "duplicate", duplicate_of: create(:feedback))

      post "/api/v1/feedback/#{feedback.feedback_id}/upvote", headers: auth_headers_for(member)

      expect(response).to have_http_status(:conflict)
    end

    it "409s on Done feedback" do
      feedback.update!(status: "approved", done_at: Time.current)

      post "/api/v1/feedback/#{feedback.feedback_id}/upvote", headers: auth_headers_for(member)

      expect(response).to have_http_status(:conflict)
      expect(json.fetch("error")).to eq("done feedback cannot be upvoted")
      expect(feedback.upvotes.count).to eq(0)
    end

    it "refuses a signed-in user without the Members role" do
      post "/api/v1/feedback/#{feedback.feedback_id}/upvote", headers: auth_headers_for(create(:user))

      expect(response).to have_http_status(:forbidden)
    end

    it "refuses the service, which is not a member" do
      post "/api/v1/feedback/#{feedback.feedback_id}/upvote", headers: service_headers

      expect(response).to have_http_status(:forbidden)
    end

    it "404s for an unknown id" do
      post "/api/v1/feedback/999999999/upvote", headers: auth_headers_for(member)

      expect(response).to have_http_status(:not_found)
    end

    it "requires authentication" do
      post "/api/v1/feedback/#{feedback.feedback_id}/upvote"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "DELETE /api/v1/feedback/:id/upvote" do
    let(:member) { create(:user, role_member: true) }
    let(:feedback) { create(:feedback) }

    it "removes the member's upvote only" do
      create(:feedback_upvote, feedback: feedback, user: member)
      create(:feedback_upvote, feedback: feedback)

      delete "/api/v1/feedback/#{feedback.feedback_id}/upvote", headers: auth_headers_for(member)

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("upvote_count" => 1, "viewer_upvoted" => false)
    end

    it "is a no-op when the member had not upvoted" do
      delete "/api/v1/feedback/#{feedback.feedback_id}/upvote", headers: auth_headers_for(member)

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("upvote_count" => 0, "viewer_upvoted" => false)
    end

    it "removes an upvote on Approved feedback that is not Done" do
      feedback.update!(status: "approved")
      create(:feedback_upvote, feedback: feedback, user: member)

      delete "/api/v1/feedback/#{feedback.feedback_id}/upvote", headers: auth_headers_for(member)

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("upvote_count" => 0)
    end

    {
      "rejected" => { rejection_reason: "No" }, "withdrawn" => {}, "approved" => { done_at: Time.current }
    }.each do |status, extra|
      it "409s and keeps the upvote on #{extra.key?(:done_at) ? 'Done' : status} feedback" do
        create(:feedback_upvote, feedback: feedback, user: member)
        feedback.update!(status: status, **extra)

        delete "/api/v1/feedback/#{feedback.feedback_id}/upvote", headers: auth_headers_for(member)

        expect(response).to have_http_status(:conflict)
        expect(feedback.upvotes.count).to eq(1)
      end
    end

    it "refuses the service" do
      delete "/api/v1/feedback/#{feedback.feedback_id}/upvote", headers: service_headers

      expect(response).to have_http_status(:forbidden)
    end

    it "requires authentication" do
      delete "/api/v1/feedback/#{feedback.feedback_id}/upvote"

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
