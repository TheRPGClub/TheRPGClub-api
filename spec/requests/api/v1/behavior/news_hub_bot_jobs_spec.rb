# frozen_string_literal: true

require "rails_helper"

# Behavior specs for the work the API asks the bot to do for the News Hub
# (spec #355, ticket #358): renewing a News Item's expired Discord image
# addresses, and catching up on what was posted while the Feature was Off.
RSpec.describe "News Hub bot jobs behavior", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:member) { create(:user, role_member: true) }
  let(:now) { Time.utc(2026, 11, 10, 12) }

  before do
    FileUtils.rm_f(BotJob::WorkSignal.path)
    travel_to now
  end

  def image(name, expires_at)
    { url: "https://cdn.discordapp.com/attachments/1/2/#{name}.png", expires_at: expires_at.iso8601 }
  end

  def record(message_id, images:, link: nil, channel_id: "1100000000000000001", posted_at: "2026-11-09T18:30:00Z")
    put "/api/v1/news_items/#{message_id}", headers: service_headers, as: :json, params: { data: {
      channel_id: channel_id, category_key: "releases", author_id: "2200000000000000002", author_name: "Ada",
      comment: nil, posted_at: posted_at, edited_at: nil, link: link, images: images
    } }
    expect(response).to have_http_status(:created).or have_http_status(:ok)
  end

  def feed(params = {})
    get "/api/v1/news_items", params: params, headers: auth_headers_for(member)
    expect(response).to have_http_status(:ok)
    json.fetch("data")
  end

  def images_of(message_id, params = {})
    feed(params).find { |item| item["message_id"] == message_id }.fetch("images")
  end

  describe "image renewal" do
    it "serves an image past its expiry as unavailable with no address, and an unexpired one normally" do
      record("3300000000000000001", images: [ image("stale", now - 1.minute), image("fresh", now + 1.hour) ])

      expect(images_of("3300000000000000001")).to eq([
        { "url" => nil, "unavailable" => true },
        { "url" => "https://cdn.discordapp.com/attachments/1/2/fresh.png", "unavailable" => false }
      ])
    end

    it "queues one renewal job naming the message, carrying the News Hub's Feature key" do
      record("3300000000000000001", channel_id: "1100000000000000009", images: [ image("stale", now - 1.minute) ])

      expect { feed }.to change(BotJob, :count).by(1)

      job = BotJob.last
      expect(job).to have_attributes(kind: "news_images_renew", status: "queued", requested_by_user_id: nil,
        summary: "Renew the expired image addresses of News Item 3300000000000000001")
      expect(job.payload).to eq("message_id" => "3300000000000000001", "channel_id" => "1100000000000000009",
        "feature_key" => "news_hub")
    end

    it "queues nothing more for that message, however often or on whichever page it is served, while the job is pending" do
      record("3300000000000000001", images: [ image("stale", now - 1.minute) ], posted_at: "2026-11-02T10:00:00Z")
      record("3300000000000000002", images: [ image("other", now - 1.minute) ], posted_at: "2026-11-01T10:00:00Z")

      expect do
        3.times { feed }
        feed(per: 1, page: 1)
        feed(per: 1, page: 2)
        feed(category: "releases")
      end.to change(BotJob, :count).by(2)
      expect(BotJob.pluck(Arel.sql("payload->>'message_id'"))).to contain_exactly(
        "3300000000000000001", "3300000000000000002"
      )

      # Still pending while the bot works on it.
      post "/api/v1/bot_jobs/claim", headers: service_headers
      expect { feed }.not_to change(BotJob, :count)
    end

    it "queues the renewal again once the earlier job has finished without renewing the address" do
      record("3300000000000000001", images: [ image("stale", now - 1.minute) ])
      feed
      BotJob.last.ack!(status: "failed", error_message: "Discord was down")

      expect { feed }.to change(BotJob, :count).by(1)
      expect(BotJob.last).to have_attributes(kind: "news_images_renew", status: "queued")
    end

    it "lets the bot see the renewal at once" do
      post "/api/v1/bot_jobs/claim", headers: service_headers # finds nothing, lowers the signal
      record("3300000000000000001", images: [ image("stale", now - 1.minute) ])

      feed

      post "/api/v1/bot_jobs/claim", headers: service_headers
      expect(json.fetch("data").map { |job| job["kind"] }).to eq(%w[news_images_renew])
    end

    it "serves the image again once the bot records the News Item with fresh addresses" do
      record("3300000000000000001", images: [ image("stale", now - 1.minute) ])
      expect(images_of("3300000000000000001")).to eq([ { "url" => nil, "unavailable" => true } ])

      record("3300000000000000001", images: [ image("renewed", now + 1.day) ])

      expect { expect(images_of("3300000000000000001")).to eq([
        { "url" => "https://cdn.discordapp.com/attachments/1/2/renewed.png", "unavailable" => false }
      ]) }.not_to change(BotJob, :count)
    end

    it "never renews a News Item whose only image is the outside site's thumbnail" do
      travel_to now + 1.year
      record("3300000000000000001", images: [],
        link: { url: "https://example.test/news", image_url: "https://example.test/img/thumb.jpg" })

      expect { feed }.not_to change(BotJob, :count)
      item = feed.sole
      expect(item.fetch("images")).to eq([])
      expect(item.dig("link", "image_url")).to eq("https://example.test/img/thumb.jpg")
    end

    it "queues nothing for unexpired images" do
      record("3300000000000000001", images: [ image("fresh", now + 1.hour) ])

      expect { feed }.not_to change(BotJob, :count)
    end
  end

  describe "catch-up" do
    let(:admin) { create(:user, role_admin: true, global_name: "Ada") }

    def set_flag(state)
      patch "/api/v1/features/news_hub", params: { data: { state: state } }, headers: auth_headers_for(admin),
        as: :json
      expect(response).to have_http_status(:ok)
    end

    def catch_up_jobs = BotJob.where(kind: "news_catch_up")

    %w[preview live].each do |state|
      it "queues one catch-up job when the News Hub goes from Off to #{state}" do
        set_feature_flag("news_hub", "off")

        expect { set_flag(state) }.to change(catch_up_jobs, :count).by(1)

        job = catch_up_jobs.sole
        expect(job).to have_attributes(status: "queued", requested_by_user_id: admin.user_id,
          summary: "News Hub catch-up: the Feature Flag went from off to #{state}")
        expect(job.payload).to eq("from_state" => "off", "to_state" => state, "feature_key" => "news_hub")
      end
    end

    {
      %w[live preview] => "Live to Preview",
      %w[preview live] => "Preview to Live",
      %w[live off] => "Live to Off",
      %w[preview off] => "Preview to Off",
      %w[live live] => "an unchanged state"
    }.each do |(from, to), label|
      it "queues none for #{label}" do
        set_feature_flag("news_hub", from)

        expect { set_flag(to) }.not_to change(catch_up_jobs, :count)
      end
    end

    it "queues none when a Feature with no stored state, which reads as Preview, goes Live", feature_flags: :none do
      expect { set_flag("live") }.not_to change(catch_up_jobs, :count)
    end

    it "queues none when another Feature leaves Off" do
      set_feature_flag("journals", "off")

      patch "/api/v1/features/journals", params: { data: { state: "live" } }, headers: auth_headers_for(admin),
        as: :json

      expect(response).to have_http_status(:ok)
      expect(catch_up_jobs).to be_empty
    end
  end
end
