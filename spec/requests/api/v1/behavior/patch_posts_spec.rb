# frozen_string_literal: true

require "rails_helper"

# Posting a Patch to Discord (spec api#510, ticket api#513). Staff post a
# published Patch to #patch-notes and push later edits; unpublishing a posted
# Patch takes the post down. Each is a bot job the staff action queues, never
# a schedule, and the bot records the post's message (or its removal) back.
RSpec.describe "api/v1/patches posting behavior", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:admin) { create(:user, role_member: true, role_admin: true) }
  let(:moderator) { create(:user, role_member: true, role_moderator: true) }
  let(:member) { create(:user, role_member: true) }

  def draft(title: "The Franchise update", cut_body: "Two things...")
    post "/api/v1/patches", params: { data: { title: title, rich_body: [], body: "Two things.", cut_body: cut_body } },
      headers: auth_headers_for(admin), as: :json
    json.dig("data", "number")
  end

  def act(action, number, as: admin, is_dev: false, headers: nil)
    post "/api/v1/patches/#{number}/#{action}", headers: headers || auth_headers_for(as, is_dev: is_dev)
  end

  def published(**fields)
    number = draft(**fields)
    act(:publish, number)
    number
  end

  def show(number)
    get "/api/v1/patches/#{number}", headers: auth_headers_for(admin)
    json.fetch("data")
  end

  # What the bot gets when it polls.
  def claimed
    post "/api/v1/bot_jobs/claim", headers: service_headers
    json.fetch("data")
  end

  def ack_done(job)
    post "/api/v1/bot_jobs/#{job.fetch('id')}/done", headers: service_headers, as: :json
  end

  # The bot records the message it posted (or edited).
  def record_post(number, channel_id: "111", message_id: "222")
    put "/api/v1/patches/#{number}/discord_post", params: { data: { channel_id: channel_id, message_id: message_id } },
      headers: service_headers, as: :json
  end

  # The bot records that it took the message down.
  def clear_post(number, message_id: "222")
    delete "/api/v1/patches/#{number}/discord_post", params: { message_id: message_id }, headers: service_headers
  end

  # A published Patch the bot has posted as message 222 in channel 111.
  def posted(**fields)
    number = published(**fields)
    act(:post, number)
    ack_done(claimed.sole)
    record_post(number)
    number
  end

  describe "Post to #patch-notes" do
    it "queues a patch_post the bot claims with the Patch's cut text" do
      number = published

      act(:post, number)

      expect(response).to have_http_status(:accepted)
      expect(json.fetch("data")).to include("kind" => "patch_post", "status" => "queued",
        "summary" => %(Post Patch #{number} "The Franchise update" to #patch-notes))
      published_at = show(number).fetch("published_at")
      expect(claimed.sole).to include("kind" => "patch_post", "payload" => {
        "number" => number, "title" => "The Franchise update", "cut_body" => "Two things...",
        "published_at" => published_at, "feature_key" => "patch_notes"
      })
    end

    it "is refused for a draft" do
      number = draft

      act(:post, number)

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("error")).to eq("not_published")
      expect(claimed).to be_empty
    end

    it "is refused once posted, and while a post is already on its way" do
      number = published
      act(:post, number)
      act(:post, number)

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("error")).to eq("post_queued")

      ack_done(claimed.sole)
      record_post(number)
      act(:post, number)

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("error")).to eq("already_posted")
    end

    it "lets a Superadmin post, and refuses Moderators, members and the service" do
      number = published

      [ auth_headers_for(moderator), auth_headers_for(member), service_headers ].each do |headers|
        act(:post, number, headers: headers)
        expect(response).to have_http_status(:forbidden)
      end
      act(:post, number, headers: {})
      expect(response).to have_http_status(:unauthorized)

      act(:post, number, as: member, is_dev: true)
      expect(response).to have_http_status(:accepted)
    end
  end

  describe "the post the bot records" do
    it "shows a Patch as posted, with its message and time" do
      number = published
      expect(show(number)).to include("posted_at" => nil, "post_channel_id" => nil, "post_message_id" => nil,
        "edited_since_post" => false)

      freeze_time do
        act(:post, number)
        ack_done(claimed.sole)
        record_post(number)

        expect(response).to have_http_status(:ok)
        expect(show(number)).to include("posted_at" => Time.current.utc.iso8601(3), "post_channel_id" => "111",
          "post_message_id" => "222", "edited_since_post" => false)
      end
    end

    it "refuses ids that aren't Discord ids, and anyone but the service" do
      number = published

      put "/api/v1/patches/#{number}/discord_post", params: { data: { channel_id: "abc", message_id: "222" } },
        headers: service_headers, as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("error")).to eq("invalid_post")

      put "/api/v1/patches/#{number}/discord_post", params: { data: { channel_id: "111", message_id: "222" } },
        headers: auth_headers_for(admin), as: :json
      expect(response).to have_http_status(:forbidden)
      delete "/api/v1/patches/#{number}/discord_post", params: { message_id: "222" }, headers: auth_headers_for(admin)
      expect(response).to have_http_status(:forbidden)
      expect(show(number)).to include("posted_at" => nil)
    end

    it "takes a post that lands after the Patch was unpublished straight down again" do
      number = published
      act(:post, number)
      ack_done(claimed.sole)
      act(:unpublish, number)
      expect(claimed).to be_empty

      record_post(number)

      expect(response).to have_http_status(:ok)
      expect(claimed.sole).to include("kind" => "patch_delete", "payload" => {
        "number" => number, "channel_id" => "111", "message_id" => "222", "feature_key" => "patch_notes"
      })
    end
  end

  describe "Update the post" do
    it "marks a posted Patch edited when its text changes, and queues a patch_edit of its message" do
      number = posted

      patch "/api/v1/patches/#{number}", params: { data: { title: "The Franchise Update", cut_body: "Three things..." } },
        headers: auth_headers_for(admin), as: :json
      expect(json.dig("data", "edited_since_post")).to be(true)

      act(:update_post, number)

      expect(response).to have_http_status(:accepted)
      expect(json.fetch("data")).to include("kind" => "patch_edit",
        "summary" => %(Update the #patch-notes post of Patch #{number} "The Franchise Update"))
      expect(claimed.sole).to include("kind" => "patch_edit", "payload" => {
        "number" => number, "title" => "The Franchise Update", "cut_body" => "Three things...",
        "published_at" => show(number).fetch("published_at"), "channel_id" => "111", "message_id" => "222",
        "feature_key" => "patch_notes"
      })
    end

    it "clears the edited mark once the bot records the edited message, keeping the posted time" do
      posted_at = nil
      number = nil
      travel_to(1.day.ago) do
        number = posted
        posted_at = show(number).fetch("posted_at")
      end
      patch "/api/v1/patches/#{number}", params: { data: { cut_body: "Three things..." } },
        headers: auth_headers_for(admin), as: :json

      act(:update_post, number)
      ack_done(claimed.sole)
      record_post(number)

      expect(show(number)).to include("edited_since_post" => false, "posted_at" => posted_at)
    end

    it "is refused when the Patch isn't posted" do
      number = published

      act(:update_post, number)

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("error")).to eq("not_posted")
      expect(claimed).to be_empty
    end

    it "refuses Moderators, members and the service" do
      number = posted

      [ auth_headers_for(moderator), auth_headers_for(member), service_headers ].each do |headers|
        act(:update_post, number, headers: headers)
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "unpublishing" do
    it "queues a patch_delete of a posted Patch's message, and the bot's record clears it" do
      number = posted

      act(:unpublish, number)

      expect(response).to have_http_status(:ok)
      expect(claimed.sole).to include("kind" => "patch_delete", "summary" => "Remove the #patch-notes post of Patch #{number}",
        "payload" => { "number" => number, "channel_id" => "111", "message_id" => "222", "feature_key" => "patch_notes" })

      clear_post(number)

      expect(response).to have_http_status(:ok)
      expect(show(number)).to include("posted_at" => nil, "post_channel_id" => nil, "post_message_id" => nil,
        "edited_since_post" => false)
    end

    it "queues nothing for a Patch that was never posted" do
      number = published

      act(:unpublish, number)

      expect(response).to have_http_status(:ok)
      expect(claimed).to be_empty
    end

    it "leaves a newer post alone when an older message's removal is recorded late" do
      number = posted
      act(:unpublish, number)
      claimed

      clear_post(number, message_id: "999")

      expect(response).to have_http_status(:ok)
      expect(show(number)).to include("post_message_id" => "222")
    end
  end

  describe "the Patch's post job" do
    it "shows writers the latest bot job for its post, so its progress survives a reload" do
      number = published
      expect(show(number)).to include("post_job" => nil)

      act(:post, number)
      job_id = json.dig("data", "id")
      post "/api/v1/bot_jobs/#{claimed.sole.fetch('id')}/failed", params: { data: { error_message: "Missing Access" } },
        headers: service_headers, as: :json

      expect(show(number).fetch("post_job")).to include("id" => job_id, "kind" => "patch_post", "status" => "failed",
        "error_message" => "Missing Access")
    end
  end

  describe "the Patch Notes Feature" do
    it "lets Admins post in Preview but not when Off" do
      set_feature_flag("patch_notes", "preview")
      number = published
      act(:post, number)
      expect(response).to have_http_status(:accepted)

      set_feature_flag("patch_notes", "off")
      act(:update_post, number)
      expect(response).to have_http_status(:not_found)
    end
  end
end
