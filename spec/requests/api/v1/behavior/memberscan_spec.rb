# frozen_string_literal: true

require "rails_helper"

# A Superadmin starts a memberscan from the site (web parity 2, #337). The
# bot does the scan as a `memberscan` bot job and reports its counts in the
# done ack's result text.
RSpec.describe "api/v1/memberscan behavior", type: :request do
  let(:superadmin) { create(:user) }
  let(:superadmin_headers) { auth_headers_for(superadmin, is_dev: true) }

  def start(headers: superadmin_headers)
    post "/api/v1/memberscan", headers: headers, as: :json
  end

  refused_callers = {
    "a plain member" => {},
    "a Members role holder" => { role_member: true },
    "a Regulars role holder" => { role_regular: true },
    "a Moderator" => { role_moderator: true },
    "an Admin" => { role_admin: true }
  }

  describe "POST /api/v1/memberscan" do
    it "queues a memberscan job requested by the Superadmin" do
      start

      expect(response).to have_http_status(:accepted)
      job = BotJob.sole
      expect(job).to have_attributes(
        kind: "memberscan", payload: {}, status: "queued", requested_by_user_id: superadmin.user_id,
        summary: "Scan the server's members and update the member list"
      )
      expect(json.fetch("data")).to include("id" => job.id, "kind" => "memberscan", "status" => "queued")
      expect(json.fetch("data")).not_to have_key("payload")
    end

    it "gives the memberscan claim a 30 minute lease" do
      start
      now = Time.current

      claimed = BotJob.poll!(limit: 1, now: now).sole

      expect(claimed.lease_expires_at).to be_within(1.second).of(now + 30.minutes)
    end

    it "lets the service start one with no requester" do
      start(headers: service_headers)

      expect(response).to have_http_status(:accepted)
      expect(BotJob.sole).to have_attributes(kind: "memberscan", requested_by_user_id: nil)
    end

    it "401s without a session" do
      start(headers: {})

      expect(response).to have_http_status(:unauthorized)
      expect(BotJob.count).to eq(0)
    end

    refused_callers.each do |label, flags|
      it "403s for #{label}" do
        start(headers: auth_headers_for(create(:user, **flags)))

        expect(response).to have_http_status(:forbidden)
        expect(BotJob.count).to eq(0)
      end
    end
  end
end
