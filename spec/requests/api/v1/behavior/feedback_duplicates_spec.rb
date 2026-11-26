# frozen_string_literal: true

require "rails_helper"

# Review outcomes beyond approve/reject (spec api#498, ticket api#501): a
# Superadmin closes Pending Feedback as a Duplicate of another, moving its
# upvotes, or changes its kind.
RSpec.describe "api/v1/feedback duplicate and kind behavior", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:superadmin) { create(:user) }
  let(:superadmin_headers) { auth_headers_for(superadmin, is_dev: true) }
  let(:feedback) { create(:feedback, kind: "bug_report", title: "Crash on save") }
  let(:original) { create(:feedback, kind: "feature_request", title: "Autosave") }

  def duplicate(id = feedback.feedback_id, original_id: original.feedback_id, headers: superadmin_headers, data: nil)
    post "/api/v1/feedback/#{id}/duplicate", params: { data: data || { original_id: original_id } },
      headers: headers, as: :json
  end

  def change_kind(kind, id = feedback.feedback_id, headers: superadmin_headers)
    post "/api/v1/feedback/#{id}/kind", params: { data: { kind: kind } }, headers: headers, as: :json
  end

  def upvoters(record)
    record.upvotes.reload.pluck(:user_id).sort
  end

  describe "POST /api/v1/feedback/:id/duplicate" do
    it "closes the Feedback onto the original and asks the bot to announce it" do
      freeze_time do
        expect { duplicate }.to change(BotJob, :count).by(1)

        expect(response).to have_http_status(:ok)
        expect(json.fetch("data")).to include(
          "feedback_id" => feedback.feedback_id, "status" => "duplicate",
          "duplicate_of_id" => original.feedback_id, "reviewed_by" => superadmin.user_id,
          "reviewed_at" => Time.current.utc.iso8601(3)
        )
        job = BotJob.last
        expect(json.dig("meta", "outcome_job_id")).to eq(job.id)
        expect(job.kind).to eq("feedback_outcome")
        expect(job.summary).to eq('Announce that the Bug Report "Crash on save" was marked a duplicate of "Autosave"')
        expect(job.payload).to eq(
          "feedback_id" => feedback.feedback_id, "kind" => "bug_report", "outcome" => "duplicate",
          "created_by" => feedback.created_by, "title" => "Crash on save",
          "github_issue_number" => nil, "github_issue_url" => nil, "rejection_reason" => nil,
          "duplicate_of_id" => original.feedback_id, "duplicate_of_title" => "Autosave",
          "feature_key" => "feedback"
        )
      end
    end

    it "moves upvotes to the original, counting each member once" do
      both, only_dup, only_orig = create_list(:user, 3)
      [ both, only_dup ].each { |user| create(:feedback_upvote, feedback: feedback, user: user) }
      [ both, only_orig ].each { |user| create(:feedback_upvote, feedback: original, user: user) }

      duplicate

      expect(response).to have_http_status(:ok)
      expect(upvoters(original)).to eq([ both, only_dup, only_orig ].map(&:user_id).sort)
      expect(upvoters(feedback)).to be_empty
      expect(json.dig("data", "upvote_count")).to eq(0)
    end

    it "resolves a Duplicate original to its root" do
      middle = create(:feedback)
      duplicate(middle.feedback_id)
      expect(response).to have_http_status(:ok)

      duplicate(original_id: middle.feedback_id)

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "duplicate_of_id")).to eq(original.feedback_id)
      expect(BotJob.last.payload).to include("duplicate_of_id" => original.feedback_id,
        "duplicate_of_title" => "Autosave")
    end

    it "repoints Duplicates of the Feedback to its new original, with their upvotes already moved" do
      earlier = create(:feedback)
      voter = create(:user)
      create(:feedback_upvote, feedback: earlier, user: voter)
      duplicate(earlier.feedback_id, original_id: feedback.feedback_id)

      duplicate

      expect(earlier.reload.duplicate_of_id).to eq(original.feedback_id)
      expect(upvoters(original)).to eq([ voter.user_id ])
    end

    it "accepts an Approved original of another kind, Done included" do
      original.update!(status: "approved", target_repo: "TheRPGClub/TheRPGClub-www", github_issue_number: 7)

      duplicate

      expect(response).to have_http_status(:ok)
    end

    %w[rejected withdrawn].each do |status|
      it "422s onto a #{status} original, changing nothing" do
        voter = create(:user)
        create(:feedback_upvote, feedback: feedback, user: voter)
        original.update!(status: status)

        expect { duplicate }.not_to change(BotJob, :count)

        expect(response).to have_http_status(:unprocessable_content)
        expect(json.fetch("error")).to include(status)
        expect(feedback.reload.status).to eq("pending")
        expect(upvoters(feedback)).to eq([ voter.user_id ])
      end
    end

    %w[approved rejected withdrawn duplicate].each do |status|
      it "409s when the Feedback is #{status}" do
        attrs = { status: status }
        attrs[:duplicate_of_id] = create(:feedback).feedback_id if status == "duplicate"
        feedback.update!(attrs)

        expect { duplicate }.not_to change(BotJob, :count)

        expect(response).to have_http_status(:conflict)
        expect(json.fetch("error")).to include(status)
      end
    end

    it "409s approval_in_progress while an approval is calling GitHub, changing nothing" do
      feedback.update_column(:approval_started_at, 10.seconds.ago)

      expect { duplicate }.not_to change(BotJob, :count)

      expect(response).to have_http_status(:conflict)
      expect(json.fetch("error")).to eq("approval_in_progress")
      expect(feedback.reload.status).to eq("pending")
    end

    it "422s onto itself, directly or through a chain" do
      duplicate(original_id: feedback.feedback_id)
      expect(response).to have_http_status(:unprocessable_content)

      other = create(:feedback)
      duplicate(other.feedback_id, original_id: feedback.feedback_id)
      duplicate(original_id: other.feedback_id)
      expect(response).to have_http_status(:unprocessable_content)
      expect(feedback.reload.status).to eq("pending")
    end

    it "422s for a missing or unknown original" do
      duplicate(data: { reviewed_by: "1" })
      expect(response).to have_http_status(:unprocessable_content)

      duplicate(original_id: 0)
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "404s for unknown Feedback" do
      duplicate(0)

      expect(response).to have_http_status(:not_found)
    end

    it "lets the bot mark a Duplicate for a Discord reviewer" do
      duplicate(data: { original_id: original.feedback_id, reviewed_by: "555" }, headers: service_headers)

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "reviewed_by")).to eq("555")
    end

    it "refuses members and Admins who are not Superadmins" do
      duplicate(headers: auth_headers_for(create(:user)))
      expect(response).to have_http_status(:forbidden)

      duplicate(headers: auth_headers_for(create(:user, role_admin: true)))
      expect(response).to have_http_status(:forbidden)
      expect(feedback.reload.status).to eq("pending")
    end
  end

  describe "POST /api/v1/feedback/:id/kind" do
    it "changes a Pending Feedback's kind" do
      change_kind("suggestion")

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "kind")).to eq("suggestion")
      expect(feedback.reload.kind).to eq("suggestion")
    end

    it "switches to a Bug Report without checking its own fields" do
      plain = create(:feedback, kind: "suggestion", details: nil)

      change_kind("bug_report", plain.feedback_id)

      expect(response).to have_http_status(:ok)
      expect(plain.reload.kind).to eq("bug_report")
    end

    it "lets the bot change it" do
      change_kind("feature_request", headers: service_headers)

      expect(response).to have_http_status(:ok)
    end

    it "422s for an unknown or missing kind" do
      change_kind("praise")
      expect(response).to have_http_status(:unprocessable_content)

      change_kind(nil)
      expect(response).to have_http_status(:unprocessable_content)
      expect(feedback.reload.kind).to eq("bug_report")
    end

    %w[approved rejected withdrawn].each do |status|
      it "409s when the Feedback is #{status}" do
        feedback.update!(status: status)

        change_kind("suggestion")

        expect(response).to have_http_status(:conflict)
        expect(feedback.reload.kind).to eq("bug_report")
      end
    end

    it "409s approval_in_progress while an approval is calling GitHub" do
      feedback.update_column(:approval_started_at, 10.seconds.ago)

      change_kind("suggestion")

      expect(response).to have_http_status(:conflict)
      expect(json.fetch("error")).to eq("approval_in_progress")
      expect(feedback.reload.kind).to eq("bug_report")
    end

    describe "a Bug Report's screenshot" do
      let(:storage) { instance_double(Backblaze::Client) }

      before do
        allow(Backblaze::Client).to receive(:new).and_return(storage)
        allow(storage).to receive(:delete_file)
        feedback.update_column(:screenshot_key, "feedback/1/shot.png")
      end

      it "is dropped, and its file removed, when the kind changes away from Bug Report" do
        change_kind("suggestion")

        expect(response).to have_http_status(:ok)
        expect(feedback.reload.screenshot_key).to be_nil
        expect(storage).to have_received(:delete_file).with(object_key: "feedback/1/shot.png")
      end

      it "is still dropped when Backblaze refuses to delete the file" do
        allow(storage).to receive(:delete_file).and_raise(Backblaze::Client::RequestError, "B2 down")

        change_kind("suggestion")

        expect(response).to have_http_status(:ok)
        expect(feedback.reload.screenshot_key).to be_nil
      end

      it "is kept when the kind stays Bug Report" do
        change_kind("bug_report")

        expect(feedback.reload.screenshot_key).to eq("feedback/1/shot.png")
        expect(storage).not_to have_received(:delete_file)
      end
    end

    it "refuses members, the author included, and Admins who are not Superadmins" do
      author = create(:user)
      own = create(:feedback, created_by: author.user_id, kind: "suggestion")

      change_kind("bug_report", own.feedback_id, headers: auth_headers_for(author))
      expect(response).to have_http_status(:forbidden)

      change_kind("bug_report", own.feedback_id, headers: auth_headers_for(create(:user, role_admin: true)))
      expect(response).to have_http_status(:forbidden)
      expect(own.reload.kind).to eq("suggestion")
    end
  end
end
