# frozen_string_literal: true

require "rails_helper"

# Behavior specs for the News Import (GLOSSARY.md, "News Hub"; spec #355,
# ticket #359): the bot records the Game News Archive's messages in batches
# as imported News Items with no News Category, and staff list the unsorted
# ones, assign their News Categories (or remove them with `skip`) and read
# the counts, through the bot.
RSpec.describe "api/v1/news_import behavior", type: :request do
  let(:member) { create(:user, role_member: true) }
  let(:admin) { create(:user, role_admin: true) }

  # What the bot sends for one archived Discord message.
  def archived(message_id, **overrides)
    {
      message_id: message_id,
      channel_id: "1100000000000000001",
      author_id: "2200000000000000002",
      author_name: "Old Timer",
      comment: "Day one buy",
      posted_at: "2021-03-04T05:06:07Z",
      edited_at: nil,
      link: {
        url: "https://example.test/news/#{message_id}",
        title: "Story #{message_id}",
        site_name: "Example News",
        description: "What happened.",
        image_url: "https://example.test/img/#{message_id}.jpg"
      },
      images: [
        { url: "https://cdn.discordapp.com/attachments/1/2/#{message_id}.png", expires_at: "2026-11-11T00:00:00Z" }
      ]
    }.merge(overrides)
  end

  def record_batch(*items, headers: service_headers)
    post "/api/v1/news_import/items", headers: headers, as: :json, params: { data: { items: items } }
  end

  def feed_ids
    get "/api/v1/news_items", headers: auth_headers_for(member)
    expect(response).to have_http_status(:ok)
    json.fetch("data").map { |item| item.fetch("message_id") }
  end

  describe "POST /api/v1/news_import/items" do
    it "records each message as an imported News Item with no News Category, hidden from the feed" do
      record_batch(archived("4400000000000000001"), archived("4400000000000000002"))

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to eq(
        "created" => 2, "updated" => 0, "previously_removed" => 0, "rejected" => []
      )
      expect(feed_ids).to be_empty
    end

    it "updates the same imported News Items when the batch is repeated, creating no duplicates" do
      record_batch(archived("4400000000000000001"), archived("4400000000000000002"))
      record_batch(archived("4400000000000000001", comment: "Changed"), archived("4400000000000000003"))

      expect(json.fetch("data")).to include("created" => 1, "updated" => 1)
      record_batch(archived("4400000000000000001"))
      expect(json.fetch("data")).to include("created" => 0, "updated" => 1)
    end

    it "rejects a message that is not a News Item with its reason, and still records the rest" do
      record_batch(archived("4400000000000000001", link: nil, images: []), archived("4400000000000000002"))

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("created" => 1, "rejected" => [
        { "index" => 0, "message_id" => "4400000000000000001", "reason" => "A News Item needs a link or at least one image" }
      ])
    end

    it "rejects a message already recorded as a live News Item and leaves that item alone" do
      live = create(:news_item, message_id: "4400000000000000001", category_key: "industry")

      record_batch(archived("4400000000000000001"))

      expect(json.fetch("data")).to include("created" => 0, "updated" => 0, "rejected" => [
        { "index" => 0, "message_id" => "4400000000000000001", "reason" => "already recorded as a live News Item" }
      ])
      expect(feed_ids).to eq([ live.message_id ])
    end

    it "rejects a message without a message id" do
      record_batch(archived(nil))

      expect(json.dig("data", "rejected")).to eq([
        { "index" => 0, "message_id" => nil, "reason" => "Message must be a Discord id" }
      ])
    end

    it "refuses more than 100 messages in one batch" do
      record_batch(*Array.new(101) { |i| archived((4_400_000_000_000_000_000 + i).to_s) })

      expect(response).to have_http_status(:unprocessable_content)
      expect(json).to eq("error" => "at most 100 items per batch")
    end

    it "is a bad request without data.items" do
      post "/api/v1/news_import/items", headers: service_headers, as: :json, params: { data: { foo: 1 } }

      expect(response).to have_http_status(:bad_request)
    end

    it "is service-only, even for staff" do
      [ member, admin ].each do |user|
        record_batch(archived("4400000000000000001"), headers: auth_headers_for(user))
        expect(response).to have_http_status(:forbidden)
      end
      expect(NewsItem.count).to eq(0)
    end
  end

  describe "GET /api/v1/news_import/items" do
    def unsorted(params = {}, acting: admin)
      get "/api/v1/news_import/items", params: { acting_user_id: acting&.user_id }.compact.merge(params),
        headers: service_headers
    end

    it "lists the unsorted imported News Items, oldest first, with the fields a classifier needs" do
      record_batch(
        archived("4400000000000000002", posted_at: "2022-01-01T00:00:00Z"),
        archived("4400000000000000001", posted_at: "2021-01-01T00:00:00Z", link: nil, comment: nil, images: [
          { url: "https://cdn.discordapp.com/attachments/1/2/a.png", expires_at: "2026-11-11T00:00:00Z" },
          { url: "https://cdn.discordapp.com/attachments/1/2/b.png", expires_at: "2026-11-11T00:00:00Z" }
        ])
      )
      create(:news_item, origin: "live")

      unsorted

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to eq([
        {
          "message_id" => "4400000000000000001", "posted_at" => "2021-01-01T00:00:00.000Z",
          "author_name" => "Old Timer", "comment" => nil, "link_url" => nil, "link_title" => nil,
          "link_site_name" => nil, "link_description" => nil, "image_count" => 2
        },
        {
          "message_id" => "4400000000000000002", "posted_at" => "2022-01-01T00:00:00.000Z",
          "author_name" => "Old Timer", "comment" => "Day one buy",
          "link_url" => "https://example.test/news/4400000000000000002", "link_title" => "Story 4400000000000000002",
          "link_site_name" => "Example News", "link_description" => "What happened.", "image_count" => 1
        }
      ])
      expect(json.fetch("meta")).to include("page" => 1, "count" => 2)
    end

    it "names an author with a member record by their current name" do
      author = create(:user, global_name: "Renamed Member")
      record_batch(archived("4400000000000000001", author_id: author.user_id))

      unsorted

      expect(json.dig("data", 0, "author_name")).to eq("Renamed Member")
    end

    it "pages with page and per" do
      record_batch(*Array.new(3) { |i| archived((4_400_000_000_000_000_000 + i).to_s) })

      unsorted({ page: 2, per: 2 })

      expect(json.fetch("data").size).to eq(1)
      expect(json.fetch("meta")).to include("page" => 2, "pages" => 2, "count" => 3, "per" => 2)
    end
  end

  describe "POST /api/v1/news_import/assignments" do
    def assign(*rows, acting: admin)
      post "/api/v1/news_import/assignments", headers: service_headers, as: :json,
        params: { data: { acting_user_id: acting.user_id, rows: rows.map { |id, value| { message_id: id, value: value } } } }
    end

    def status
      get "/api/v1/news_import/status", params: { acting_user_id: admin.user_id }, headers: service_headers
      json.fetch("data")
    end

    def unsorted_ids
      get "/api/v1/news_import/items", params: { acting_user_id: admin.user_id }, headers: service_headers
      json.fetch("data").map { |item| item.fetch("message_id") }
    end

    before do
      record_batch(*%w[4400000000000000001 4400000000000000002 4400000000000000003].map { |id| archived(id) })
    end

    it "assigns a News Category, which shows the item in the feed with its original author and date" do
      assign([ "4400000000000000001", "releases" ], [ "4400000000000000002", " Industry " ])

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to eq(
        "assigned" => 2, "removed" => 0, "rejected" => 0, "unsorted" => 1, "rejections" => []
      )

      get "/api/v1/news_items", params: { category: "releases" }, headers: auth_headers_for(member)
      expect(json.fetch("data")).to contain_exactly(include(
        "message_id" => "4400000000000000001", "category_key" => "releases", "origin" => "import",
        "posted_at" => "2021-03-04T05:06:07.000Z",
        "author" => { "user_id" => "2200000000000000002", "name" => "Old Timer", "member" => false }
      ))
      expect(feed_ids).to contain_exactly("4400000000000000001", "4400000000000000002")
      expect(unsorted_ids).to eq([ "4400000000000000003" ])
    end

    it "changes the News Category of an imported item when assigned again" do
      assign([ "4400000000000000001", "releases" ])
      assign([ "4400000000000000001", "rumours" ])

      expect(json.fetch("data")).to include("assigned" => 1)
      get "/api/v1/news_items", params: { category: "rumours" }, headers: auth_headers_for(member)
      expect(json.fetch("data").map { |item| item.fetch("message_id") }).to eq([ "4400000000000000001" ])
    end

    it "keeps an assigned News Category when the batch is recorded again" do
      assign([ "4400000000000000001", "hardware" ])

      record_batch(archived("4400000000000000001", comment: "Rescanned"))

      expect(json.fetch("data")).to include("updated" => 1, "rejected" => [])
      get "/api/v1/news_items", params: { category: "hardware" }, headers: auth_headers_for(member)
      expect(json.fetch("data")).to contain_exactly(include("message_id" => "4400000000000000001",
        "comment" => "Rescanned"))
    end

    it "removes an item with skip and remembers it, so a re-scan does not bring it back" do
      assign([ "4400000000000000001", "skip" ], [ "4400000000000000002", "SKIP" ])

      expect(json.fetch("data")).to include("assigned" => 0, "removed" => 2, "unsorted" => 1)
      expect(unsorted_ids).to eq([ "4400000000000000003" ])

      record_batch(archived("4400000000000000001"), archived("4400000000000000004"))
      expect(json.fetch("data")).to eq(
        "created" => 1, "updated" => 0, "previously_removed" => 1, "rejected" => []
      )
      expect(unsorted_ids).to eq(%w[4400000000000000003 4400000000000000004])
      expect(feed_ids).to be_empty
    end

    it "counts skip again for an item already removed, so the same file can be uploaded twice" do
      assign([ "4400000000000000001", "skip" ], [ "4400000000000000002", "general" ])
      assign([ "4400000000000000001", "skip" ], [ "4400000000000000002", "general" ])

      expect(json.fetch("data")).to include("assigned" => 1, "removed" => 1, "rejected" => 0)
      expect(status).to eq("sorted" => 1, "unsorted" => 1, "removed" => 1)
    end

    it "rejects bad rows one by one with a reason and still applies the valid ones" do
      live = create(:news_item, message_id: "4400000000000000009", category_key: "industry")
      assign([ "4400000000000000001", "skip" ])

      assign(
        [ "4400000000000000002", "releases" ],
        [ "4400000000000000404", "releases" ],
        [ "4400000000000000003", "piracy" ],
        [ "4400000000000000003", "" ],
        [ "4400000000000000009", "general" ],
        [ "4400000000000000001", "general" ],
        [ "", "general" ]
      )

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to eq(
        "assigned" => 1, "removed" => 0, "rejected" => 6, "unsorted" => 1,
        "rejections" => [
          { "index" => 1, "message_id" => "4400000000000000404", "value" => "releases",
            "reason" => "unknown message ID" },
          { "index" => 2, "message_id" => "4400000000000000003", "value" => "piracy",
            "reason" => "message ID appears more than once" },
          { "index" => 3, "message_id" => "4400000000000000003", "value" => "",
            "reason" => "message ID appears more than once" },
          { "index" => 4, "message_id" => "4400000000000000009", "value" => "general",
            "reason" => "not an imported News Item" },
          { "index" => 5, "message_id" => "4400000000000000001", "value" => "general",
            "reason" => "removed with skip" },
          { "index" => 6, "message_id" => "", "value" => "general", "reason" => "missing message ID" }
        ]
      )
      expect(feed_ids).to contain_exactly("4400000000000000002", live.message_id)
      get "/api/v1/news_items", params: { category: "industry" }, headers: auth_headers_for(member)
      expect(json.fetch("data").map { |item| item.fetch("message_id") }).to eq([ live.message_id ])
    end

    it "rejects an invalid or blank value with the accepted values" do
      assign([ "4400000000000000002", "piracy" ], [ "4400000000000000003", " " ])

      expect(json.fetch("data").fetch("rejections").map { |row| row.fetch("reason") }).to eq([
        "invalid value: expected one of #{NewsCategory.keys.join(', ')} or skip",
        "no value: expected one of #{NewsCategory.keys.join(', ')} or skip"
      ])
    end

    it "refuses more than 5000 rows in one request" do
      assign(*Array.new(5001) { |i| [ (4_400_000_000_000_000_000 + i).to_s, "general" ] })

      expect(response).to have_http_status(:unprocessable_content)
      expect(json).to eq("error" => "at most 5000 rows per request")
    end

    it "is a bad request without data.rows" do
      post "/api/v1/news_import/assignments", headers: service_headers, as: :json,
        params: { data: { acting_user_id: admin.user_id } }

      expect(response).to have_http_status(:bad_request)
    end
  end

  describe "GET /api/v1/news_import/status" do
    it "counts imported items that are sorted, unsorted and removed, leaving live items out" do
      record_batch(*Array.new(4) { |i| archived((4_400_000_000_000_000_000 + i).to_s) })
      create(:news_item, origin: "live")
      post "/api/v1/news_import/assignments", headers: service_headers, as: :json, params: { data: {
        acting_user_id: admin.user_id,
        rows: [ { message_id: "4400000000000000000", value: "general" }, { message_id: "4400000000000000001", value: "skip" } ]
      } }

      get "/api/v1/news_import/status", params: { acting_user_id: admin.user_id }, headers: service_headers

      expect(response).to have_http_status(:ok)
      expect(json).to eq("data" => { "sorted" => 1, "unsorted" => 2, "removed" => 1 })
    end
  end

  describe "the Admin or Superadmin requirement" do
    endpoints = {
      "listing" => ->(params) { get "/api/v1/news_import/items", params: params, headers: service_headers },
      "status" => ->(params) { get "/api/v1/news_import/status", params: params, headers: service_headers },
      "assigning" => lambda { |params|
        post "/api/v1/news_import/assignments", headers: service_headers, as: :json,
          params: { data: params.merge(rows: []) }
      }
    }

    endpoints.each do |name, call|
      describe name do
        it "answers the bot for an acting Admin or Superadmin in Preview and Live" do
          superadmin = create(:user, role_dev: true)

          %w[preview live].each do |state|
            set_feature_flag("news_hub", state)
            [ admin, superadmin ].each do |user|
              instance_exec({ acting_user_id: user.user_id }, &call)
              expect(response).to have_http_status(:ok), "#{state}: got #{response.status}"
            end
          end
        end

        it "refuses the bot for an acting member who is not an Admin or Superadmin, in every Feature state" do
          moderator = create(:user, role_moderator: true)

          %w[off preview live].each do |state|
            set_feature_flag("news_hub", state)
            [ member, moderator ].each do |user|
              instance_exec({ acting_user_id: user.user_id }, &call)
              expect(response).to have_http_status(:forbidden), "#{state}: got #{response.status}"
            end
            instance_exec({ acting_user_id: "999999999999999999" }, &call)
            expect(response).to have_http_status(:forbidden)
          end
        end

        it "is a bad request from the bot without an acting member" do
          instance_exec({}, &call)

          expect(response).to have_http_status(:bad_request)
          expect(json).to eq("error" => "acting_user_id required")
        end
      end
    end

    it "answers a signed-in Admin or Superadmin and refuses a signed-in member" do
      get "/api/v1/news_import/status", headers: auth_headers_for(admin)
      expect(response).to have_http_status(:ok)
      get "/api/v1/news_import/status", headers: auth_headers_for(member, is_dev: true)
      expect(response).to have_http_status(:ok)

      get "/api/v1/news_import/status", headers: auth_headers_for(member)
      expect(response).to have_http_status(:forbidden)
    end

    it "is not found for signed-in staff while the News Hub is Off" do
      set_feature_flag("news_hub", "off")

      get "/api/v1/news_import/status", headers: auth_headers_for(admin)

      expect(response).to have_http_status(:not_found)
    end
  end
end
