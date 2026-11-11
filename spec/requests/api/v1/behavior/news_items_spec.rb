# frozen_string_literal: true

require "rails_helper"

# Behavior specs for the News Hub's backbone (spec #355, ticket #356): the
# News Hub Feature, the fixed list of News Categories, the bot recording and
# removing News Items with the service token, and the members' feed.
RSpec.describe "api/v1/news_items behavior", type: :request do
  let(:member) { create(:user, role_member: true) }

  def snowflake = SecureRandom.random_number(10**18).to_s

  # What the bot sends for one Discord message: a link with its preview, one
  # image attachment and the member's comment.
  def item_payload(**overrides)
    {
      channel_id: "1100000000000000001",
      category_key: "releases",
      author_id: "2200000000000000002",
      author_name: "Ada",
      comment: "Finally!",
      posted_at: "2026-11-09T18:30:00Z",
      edited_at: nil,
      link: {
        url: "https://example.test/news/elden-ring-2",
        title: "Elden Ring 2 announced",
        site_name: "Example News",
        description: "FromSoftware's next game.",
        image_url: "https://example.test/img/er2.jpg"
      },
      images: [
        { url: "https://cdn.discordapp.com/attachments/1/2/shot.png?ex=1", expires_at: "2099-11-10T18:30:00Z" }
      ]
    }.merge(overrides)
  end

  def record(message_id, **overrides)
    put "/api/v1/news_items/#{message_id}", headers: service_headers, as: :json,
      params: { data: item_payload(**overrides) }
  end

  def feed(params = {})
    get "/api/v1/news_items", params: params, headers: auth_headers_for(member)
    expect(response).to have_http_status(:ok)
    json
  end

  def feed_ids(params = {}) = feed(params).fetch("data").map { |item| item.fetch("message_id") }

  describe "PUT /api/v1/news_items/:message_id" do
    it "records a News Item the API has not seen, with everything the message carries" do
      record("3300000000000000003")

      expect(response).to have_http_status(:created)
      expect(json.fetch("data")).to eq(
        "message_id" => "3300000000000000003",
        "category_key" => "releases",
        "origin" => "live",
        "comment" => "Finally!",
        "posted_at" => "2026-11-09T18:30:00.000Z",
        "edited_at" => nil,
        "link" => {
          "url" => "https://example.test/news/elden-ring-2",
          "title" => "Elden Ring 2 announced",
          "site_name" => "Example News",
          "description" => "FromSoftware's next game.",
          "image_url" => "https://example.test/img/er2.jpg"
        },
        "images" => [
          { "url" => "https://cdn.discordapp.com/attachments/1/2/shot.png?ex=1", "unavailable" => false }
        ],
        "author" => { "user_id" => "2200000000000000002", "name" => "Ada", "member" => false },
        "picked_category_key" => nil,
        "news_copy" => nil
      )
      expect(feed_ids).to eq([ "3300000000000000003" ])
    end

    it "updates the same News Item when the message is recorded again, so recording is idempotent" do
      record("3300000000000000003", link: { url: "https://example.test/a" }, comment: nil)
      expect(json.dig("data", "link")).to eq(
        "url" => "https://example.test/a", "title" => nil, "site_name" => nil, "description" => nil, "image_url" => nil
      )

      # Discord's link preview arrives a moment later as an edit.
      record("3300000000000000003", link: { url: "https://example.test/a", title: "A" }, comment: nil)
      expect(response).to have_http_status(:ok)
      record("3300000000000000003", link: { url: "https://example.test/a", title: "A" }, comment: nil)
      expect(response).to have_http_status(:ok)

      data = feed.fetch("data")
      expect(data.size).to eq(1)
      expect(data.first.dig("link", "title")).to eq("A")
      expect(feed.dig("meta", "count")).to eq(1)
    end

    describe "the News Channel's picked category and News Copy (ticket #368)" do
      let(:copy) { { message_id: "5500000000000000005", thread_id: "6600000000000000006" } }

      it "stores the category the bot picked and where the News Copy lives" do
        record("3300000000000000003", picked_category_key: "rumours", category_key: "rumours", news_copy: copy)

        expect(response).to have_http_status(:created)
        expect(json.fetch("data")).to include(
          "category_key" => "rumours", "picked_category_key" => "rumours",
          "news_copy" => { "message_id" => "5500000000000000005", "thread_id" => "6600000000000000006" }
        )
      end

      it "leaves the stored picked category and News Copy alone when a recording omits them" do
        record("3300000000000000003", picked_category_key: "rumours", category_key: "rumours", news_copy: copy)

        record("3300000000000000003", category_key: "rumours", comment: "Edited")

        expect(response).to have_http_status(:ok)
        expect(json.fetch("data")).to include(
          "comment" => "Edited", "picked_category_key" => "rumours",
          "news_copy" => { "message_id" => "5500000000000000005", "thread_id" => "6600000000000000006" }
        )
      end

      it "keeps the stored News Category when an update omits it, so an edit need not know a correction" do
        record("3300000000000000003", category_key: "industry")
        payload = item_payload(comment: "Edited").except(:category_key)

        put "/api/v1/news_items/3300000000000000003", headers: service_headers, as: :json, params: { data: payload }

        expect(response).to have_http_status(:ok)
        expect(json.fetch("data")).to include("category_key" => "industry", "comment" => "Edited")
      end

      it "still needs a News Category to record a new live News Item" do
        put "/api/v1/news_items/3300000000000000003", headers: service_headers, as: :json,
          params: { data: item_payload.except(:category_key) }

        expect(response).to have_http_status(:unprocessable_content)
      end

      it "forgets the News Copy when the bot reports none" do
        record("3300000000000000003", news_copy: copy)

        record("3300000000000000003", news_copy: nil)

        expect(response).to have_http_status(:ok)
        expect(json.dig("data", "news_copy")).to be_nil
      end

      it "records only a News Copy's location on an existing News Item, changing nothing else" do
        record("3300000000000000003", picked_category_key: "releases", edited_at: "2026-11-09T19:00:00Z")
        before = json.fetch("data")

        put "/api/v1/news_items/3300000000000000003", headers: service_headers, as: :json,
          params: { data: { news_copy: copy } }

        expect(response).to have_http_status(:ok)
        after = json.fetch("data")
        expect(after).to eq(before.merge(
          "news_copy" => { "message_id" => "5500000000000000005", "thread_id" => "6600000000000000006" }
        ))
        expect(feed.fetch("data")).to eq([ after ])
      end

      it "records a News Copy's location on an imported News Item, which keeps its staff-assigned category" do
        create(:news_item, message_id: "3300000000000000003", origin: "import", category_key: "industry")

        put "/api/v1/news_items/3300000000000000003", headers: service_headers, as: :json,
          params: { data: { news_copy: copy } }

        expect(response).to have_http_status(:ok)
        expect(json.fetch("data")).to include("origin" => "import", "category_key" => "industry",
          "news_copy" => { "message_id" => "5500000000000000005", "thread_id" => "6600000000000000006" })
      end

      it "is not found when only a News Copy is reported for a message never recorded" do
        put "/api/v1/news_items/3300000000000000003", headers: service_headers, as: :json,
          params: { data: { news_copy: copy } }

        expect(response).to have_http_status(:not_found)
      end

      it "rejects a News Copy location that is not two Discord ids" do
        record("3300000000000000003", news_copy: { message_id: "5500000000000000005" })
        expect(response).to have_http_status(:unprocessable_content)
        expect(json.fetch("error")).to match(/news copy/i)

        record("3300000000000000003", news_copy: { message_id: "abc", thread_id: "6600000000000000006" })
        expect(response).to have_http_status(:unprocessable_content)
      end

      it "rejects an unknown picked category" do
        record("3300000000000000003", picked_category_key: "piracy")

        expect(response).to have_http_status(:unprocessable_content)
        expect(json.fetch("error")).to match(/picked category/i)
      end
    end

    it "records an image-only News Item and keeps its images in order" do
      record("3300000000000000003", link: nil, comment: "", images: [
        { url: "https://cdn.discordapp.com/attachments/1/2/first.png", expires_at: "2099-11-10T18:30:00Z" },
        { url: "https://cdn.discordapp.com/attachments/1/3/second.png", expires_at: "2099-11-10T18:30:00Z" }
      ])

      expect(response).to have_http_status(:created)
      expect(json.dig("data", "link")).to be_nil
      expect(json.dig("data", "comment")).to be_nil
      expect(json.dig("data", "images").map { |image| image.fetch("url") }).to eq([
        "https://cdn.discordapp.com/attachments/1/2/first.png", "https://cdn.discordapp.com/attachments/1/3/second.png"
      ])
    end

    it "records an edit's time and the new comment" do
      record("3300000000000000003")
      record("3300000000000000003", comment: "Edited take", edited_at: "2026-11-09T19:00:00Z")

      expect(json.fetch("data")).to include("comment" => "Edited take", "edited_at" => "2026-11-09T19:00:00.000Z")
    end

    it "starts recording a message that begins to qualify after an edit" do
      record("3300000000000000003", link: nil, images: [])
      expect(response).to have_http_status(:unprocessable_content)

      record("3300000000000000003", link: { url: "https://example.test/added" }, images: [])
      expect(response).to have_http_status(:created)
      expect(feed_ids).to eq([ "3300000000000000003" ])
    end

    it "rejects a message with neither a link nor an image, which is not a News Item" do
      record("3300000000000000003", link: nil, images: [])

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("error")).to match(/link or at least one image/)
    end

    it "rejects an unknown News Category" do
      record("3300000000000000003", category_key: "piracy")

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("error")).to match(/category/i)
    end

    it "rejects a live News Item with no News Category" do
      record("3300000000000000003", category_key: nil)

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "rejects an image whose expiry is not an ISO 8601 time" do
      record("3300000000000000003", images: [
        { url: "https://cdn.discordapp.com/attachments/1/2/x.png", expires_at: "next tuesday" }
      ])

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "records an image with no expiry (an unsigned address), which is always served" do
      record("3300000000000000003", images: [
        { url: "https://cdn.discordapp.com/attachments/1/2/x.png", expires_at: nil }
      ])

      expect(response).to have_http_status(:created)
      expect(json.dig("data", "images")).to eq([
        { "url" => "https://cdn.discordapp.com/attachments/1/2/x.png", "unavailable" => false }
      ])
    end

    it "requires a data object" do
      put "/api/v1/news_items/3300000000000000003", headers: service_headers, as: :json, params: {}

      expect(response).to have_http_status(:bad_request)
    end

    it "keeps the News Category staff assigned to an imported News Item when it is recorded again" do
      create(:news_item, message_id: "3300000000000000003", origin: "import", category_key: "industry")

      record("3300000000000000003", category_key: nil, comment: "Fresh")

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("category_key" => "industry", "origin" => "import", "comment" => "Fresh")
      record("3300000000000000003", category_key: "general")
      expect(json.fetch("data")).to include("category_key" => "industry")
    end

    it "is service-only" do
      [ member, create(:user, :admin) ].each do |user|
        put "/api/v1/news_items/3300000000000000003", headers: auth_headers_for(user), as: :json,
          params: { data: item_payload }
        expect(response).to have_http_status(:forbidden)
      end
      put "/api/v1/news_items/3300000000000000003", headers: auth_headers_for(member, is_dev: true), as: :json,
        params: { data: item_payload }
      expect(response).to have_http_status(:forbidden)
    end

    it "drops null characters from the message's text, which PostgreSQL cannot store" do
      record("3300000000000000003",
        author_name: "A\u0000da", comment: "Fin\u0000ally!",
        link: item_payload[:link].merge(title: "Elden Ring\u0000 2", description: "\u0000"),
        images: [ { url: "https://cdn.discordapp.com/a/1/2/s.png?ex=1\u0000", expires_at: nil } ])

      expect(response).to have_http_status(:created)
      data = json.fetch("data")
      expect(data.fetch("comment")).to eq("Finally!")
      expect(data.fetch("author").fetch("name")).to eq("Ada")
      expect(data.fetch("link")).to include("title" => "Elden Ring 2", "description" => nil)
      expect(data.fetch("images")).to eq([ { "url" => "https://cdn.discordapp.com/a/1/2/s.png?ex=1", "unavailable" => false } ])
    end

    it "records while the News Hub is Off, since the bot runs its own feature gate" do
      set_feature_flag("news_hub", "off")

      record("3300000000000000003")

      expect(response).to have_http_status(:created)
    end
  end

  describe "DELETE /api/v1/news_items/:message_id" do
    it "removes the News Item for good" do
      record("3300000000000000003")
      record("3300000000000000004")

      delete "/api/v1/news_items/3300000000000000003", headers: service_headers

      expect(response).to have_http_status(:ok)
      expect(feed_ids).to eq([ "3300000000000000004" ])
      record("3300000000000000003")
      expect(response).to have_http_status(:created)
    end

    it "answers with where the removed item's News Copy lives, so the bot can delete it" do
      record("3300000000000000003", news_copy: { message_id: "5500000000000000005", thread_id: "6600000000000000006" })

      delete "/api/v1/news_items/3300000000000000003", headers: service_headers

      expect(response).to have_http_status(:ok)
      expect(json).to eq("data" => { "removed" => true,
        "news_copy" => { "message_id" => "5500000000000000005", "thread_id" => "6600000000000000006" } })
    end

    it "answers with no News Copy when the removed item had none" do
      record("3300000000000000003")

      delete "/api/v1/news_items/3300000000000000003", headers: service_headers

      expect(json).to eq("data" => { "removed" => true, "news_copy" => nil })
    end

    it "succeeds for a message the API never recorded, so the bot need not know" do
      delete "/api/v1/news_items/404404404404404404", headers: service_headers

      expect(response).to have_http_status(:ok)
      expect(json).to eq("data" => { "removed" => false, "news_copy" => nil })
    end

    it "is service-only" do
      record("3300000000000000003")

      delete "/api/v1/news_items/3300000000000000003", headers: auth_headers_for(create(:user, :admin))

      expect(response).to have_http_status(:forbidden)
      expect(feed_ids).to eq([ "3300000000000000003" ])
    end
  end

  describe "GET /api/v1/news_items" do
    it "lists News Items newest first" do
      record("3300000000000000001", posted_at: "2026-11-01T10:00:00Z")
      record("3300000000000000003", posted_at: "2026-11-03T10:00:00Z")
      record("3300000000000000002", posted_at: "2026-11-02T10:00:00Z")

      expect(feed_ids).to eq(%w[3300000000000000003 3300000000000000002 3300000000000000001])
    end

    it "pages the standard way" do
      5.times { |i| record("330000000000000000#{i}", posted_at: "2026-11-0#{i + 1}T10:00:00Z") }

      body = feed(page: 2, per: 2)

      expect(body.fetch("data").map { |item| item["message_id"] }).to eq(%w[3300000000000000002 3300000000000000001])
      expect(body.fetch("meta")).to include("page" => 2, "pages" => 3, "count" => 5, "per" => 2, "prev" => 1, "next" => 3)
    end

    it "filters by one News Category" do
      record("3300000000000000001", category_key: "releases")
      record("3300000000000000002", category_key: "industry")

      expect(feed_ids(category: "industry")).to eq(%w[3300000000000000002])
    end

    it "filters by several News Categories, comma-separated or repeated" do
      record("3300000000000000001", category_key: "releases", posted_at: "2026-11-01T10:00:00Z")
      record("3300000000000000002", category_key: "industry", posted_at: "2026-11-02T10:00:00Z")
      record("3300000000000000003", category_key: "rumours", posted_at: "2026-11-03T10:00:00Z")

      expect(feed_ids(category: "releases,rumours")).to eq(%w[3300000000000000003 3300000000000000001])
      expect(feed_ids(category: %w[releases industry])).to eq(%w[3300000000000000002 3300000000000000001])
      expect(feed(category: "releases,rumours").dig("meta", "count")).to eq(2)
    end

    it "rejects an unknown News Category key" do
      get "/api/v1/news_items", params: { category: "releases,piracy" }, headers: auth_headers_for(member)

      expect(response).to have_http_status(:bad_request)
      expect(json).to eq("error" => "unknown category: piracy")
    end

    it "never returns a News Item that has no News Category" do
      record("3300000000000000001")
      create(:news_item, message_id: "3300000000000000002", origin: "import", category_key: nil)

      expect(feed_ids).to eq(%w[3300000000000000001])
      expect(feed.dig("meta", "count")).to eq(1)
      get "/api/v1/news_items", headers: service_headers
      expect(json.fetch("data").map { |item| item["message_id"] }).to eq(%w[3300000000000000001])
    end

    it "shows an imported News Item once it has a News Category, with its original author and date" do
      create(:news_item, message_id: "3300000000000000002", origin: "import", category_key: "industry",
        author_name: "Old Timer", posted_at: Time.utc(2021, 5, 4, 12))

      item = feed.fetch("data").first

      expect(item).to include("message_id" => "3300000000000000002", "origin" => "import",
        "category_key" => "industry", "posted_at" => "2021-05-04T12:00:00.000Z")
      expect(item.fetch("author")).to include("name" => "Old Timer", "member" => false)
    end

    it "names an author by their current member name, and by the recorded name when they have no record" do
      poster = create(:user, global_name: "Ada Lovelace", username: "ada")
      plain = create(:user, global_name: nil, username: "babbage")
      record("3300000000000000001", author_id: poster.user_id, author_name: "Ada (old nick)",
        posted_at: "2026-11-03T10:00:00Z")
      record("3300000000000000002", author_id: plain.user_id, author_name: "Charles", posted_at: "2026-11-02T10:00:00Z")
      record("3300000000000000003", author_id: "4400000000000000004", author_name: "Long Gone",
        posted_at: "2026-11-01T10:00:00Z")

      expect(feed.fetch("data").map { |item| item.fetch("author") }).to eq([
        { "user_id" => poster.user_id, "name" => "Ada Lovelace", "member" => true },
        { "user_id" => plain.user_id, "name" => "babbage", "member" => true },
        { "user_id" => "4400000000000000004", "name" => "Long Gone", "member" => false }
      ])
    end

    it "carries each image with an unavailable marker, false while the address is served" do
      record("3300000000000000001")

      expect(feed.fetch("data").first.fetch("images")).to eq([
        { "url" => "https://cdn.discordapp.com/attachments/1/2/shot.png?ex=1", "unavailable" => false }
      ])
    end

    describe "behind the News Hub Feature" do
      let(:admin) { create(:user, role_admin: true) }

      before { record("3300000000000000001") }

      it "answers members while Live" do
        expect(feed_ids).to eq(%w[3300000000000000001])
      end

      it "is not found for a member while in Preview, and answers staff" do
        set_feature_flag("news_hub", "preview")

        get "/api/v1/news_items", headers: auth_headers_for(member)
        expect(response).to have_http_status(:not_found)
        expect(json).to eq("error" => "not_found")
        get "/api/v1/news_items", headers: auth_headers_for(admin)
        expect(response).to have_http_status(:ok)
      end

      it "is not found for everyone while Off" do
        set_feature_flag("news_hub", "off")

        [ member, admin ].each do |user|
          get "/api/v1/news_items", headers: auth_headers_for(user)
          expect(response).to have_http_status(:not_found)
        end
      end
    end

    it "requires a sign-in" do
      get "/api/v1/news_items"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/news_items/uncopied (ticket #368)" do
    def uncopied(params = {})
      get "/api/v1/news_items/uncopied", params: params, headers: service_headers
      expect(response).to have_http_status(:ok)
      json
    end

    def uncopied_ids(params = {}) = uncopied(params).fetch("data").map { |item| item.fetch("message_id") }

    it "lists the News Items with a News Category but no News Copy, oldest first, live and imported alike" do
      record("3300000000000000003", posted_at: "2026-11-03T10:00:00Z")
      record("3300000000000000001", posted_at: "2026-11-01T10:00:00Z",
        news_copy: { message_id: "5500000000000000005", thread_id: "6600000000000000006" })
      create(:news_item, message_id: "3300000000000000002", origin: "import", category_key: "industry",
        posted_at: Time.utc(2021, 5, 4, 12))
      create(:news_item, message_id: "3300000000000000004", origin: "import", category_key: nil,
        posted_at: Time.utc(2020, 1, 1))

      expect(uncopied_ids).to eq(%w[3300000000000000002 3300000000000000003])
      expect(uncopied.dig("meta", "count")).to eq(2)
      expect(uncopied.fetch("data").first).to include("origin" => "import", "category_key" => "industry",
        "posted_at" => "2021-05-04T12:00:00.000Z", "news_copy" => nil)
    end

    it "pages the standard way, keeping posting order for items posted at the same time" do
      5.times { |i| record("330000000000000000#{i}", posted_at: "2026-11-0#{i + 1}T10:00:00Z") }
      record("3300000000000000009", posted_at: "2026-11-01T10:00:00Z")

      body = uncopied(page: 2, per: 2)

      expect(body.fetch("data").map { |item| item["message_id"] }).to eq(%w[3300000000000000001 3300000000000000002])
      expect(body.fetch("meta")).to include("page" => 2, "pages" => 3, "count" => 6, "per" => 2)
      expect(uncopied_ids(per: 2)).to eq(%w[3300000000000000000 3300000000000000009])
    end

    it "drops an item once its News Copy is reported, and lists it again when the copy is gone" do
      record("3300000000000000001")
      copy = { message_id: "5500000000000000005", thread_id: "6600000000000000006" }

      put "/api/v1/news_items/3300000000000000001", headers: service_headers, as: :json,
        params: { data: { news_copy: copy } }
      expect(uncopied_ids).to eq([])

      put "/api/v1/news_items/3300000000000000001", headers: service_headers, as: :json,
        params: { data: { news_copy: nil } }
      expect(uncopied_ids).to eq(%w[3300000000000000001])
    end

    describe "narrowed by origin" do
      before do
        record("3300000000000000003", posted_at: "2026-11-03T10:00:00Z")
        create(:news_item, message_id: "3300000000000000002", origin: "import", category_key: "industry",
          posted_at: Time.utc(2021, 5, 4, 12))
      end

      it "lists only live News Items for origin=live, so catch-up leaves imported ones to the history copy" do
        body = uncopied(origin: "live")

        expect(body.fetch("data").map { |item| item["message_id"] }).to eq(%w[3300000000000000003])
        expect(body.dig("meta", "count")).to eq(1)
      end

      it "lists only imported News Items for origin=import" do
        expect(uncopied_ids(origin: "import")).to eq(%w[3300000000000000002])
      end

      it "lists both when origin is omitted" do
        expect(uncopied_ids).to eq(%w[3300000000000000002 3300000000000000003])
      end

      it "rejects an unknown origin" do
        get "/api/v1/news_items/uncopied", params: { origin: "forum" }, headers: service_headers

        expect(response).to have_http_status(:unprocessable_content)
        expect(json).to eq("error" => "unknown origin: forum (expected live or import)")
      end
    end

    it "answers the bot while the News Hub is Off" do
      set_feature_flag("news_hub", "off")
      record("3300000000000000001")

      expect(uncopied_ids).to eq(%w[3300000000000000001])
    end

    it "is service-only" do
      [ member, create(:user, :admin) ].each do |user|
        get "/api/v1/news_items/uncopied", headers: auth_headers_for(user)
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "the News Hub Feature" do
    it "is a hideable Feature that reads as Preview with no stored state", feature_flags: :none do
      admin = create(:user, role_admin: true)

      get "/api/v1/features", headers: auth_headers_for(admin)

      news_hub = json.fetch("data").find { |feature| feature["key"] == "news_hub" }
      expect(news_hub).to include("name" => "News Hub", "state" => "preview", "core" => false, "hideable" => true,
        "last_change" => nil)
    end
  end

  describe "GET /api/v1/news_categories" do
    it "lists the seven News Categories in order, with key and name" do
      get "/api/v1/news_categories", headers: auth_headers_for(create(:user, role_member: true))

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to eq([
        { "key" => "announcements", "name" => "Announcements & Trailers", "position" => 1 },
        { "key" => "releases", "name" => "Releases & Updates", "position" => 2 },
        { "key" => "emulation", "name" => "Emulation & Preservation", "position" => 3 },
        { "key" => "industry", "name" => "Industry", "position" => 4 },
        { "key" => "hardware", "name" => "Hardware & Platforms", "position" => 5 },
        { "key" => "rumours", "name" => "Rumours & Leaks", "position" => 6 },
        { "key" => "general", "name" => "General", "position" => 7 }
      ])
    end

    it "answers the bot's service token" do
      get "/api/v1/news_categories", headers: service_headers

      expect(json.fetch("data").size).to eq(7)
    end

    it "is not found for a member while the News Hub is in Preview" do
      set_feature_flag("news_hub", "preview")

      get "/api/v1/news_categories", headers: auth_headers_for(create(:user, role_member: true))

      expect(response).to have_http_status(:not_found)
    end
  end
end
