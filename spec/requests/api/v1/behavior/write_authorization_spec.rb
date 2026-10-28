# frozen_string_literal: true

require "rails_helper"

# Cross-controller write authorization (GHSA-h7cf-53h7-8gxw):
#
# - collection writes are owner-restricted like the other user-game lists;
# - owner-checked writes only accept their editable columns, so an owner
#   cannot move a record onto another member (`user_id`) or rewrite its key;
# - import items are service-only (the bot drives the review loop);
# - bot-community data (RSS, starboard, reminders, suggestions, legacy voting
#   info) is writable only by the bot or an admin.
RSpec.describe "api/v1 write authorization", type: :request do
  let(:owner) { create(:user) }
  let(:victim) { create(:user) }
  let(:admin) { create(:user, role_admin: true) }

  describe "collections" do
    it "rejects a non-owner create, update and destroy" do
      entry = create(:collection_entry, user: victim, note: "mine")

      post "/api/v1/users/#{victim.user_id}/collections",
        params: { data: { gamedb_game_id: create(:game).game_id, ownership_type: "Digital" } },
        headers: auth_headers_for(owner), as: :json
      expect(response).to have_http_status(:forbidden)

      patch "/api/v1/collections/#{entry.entry_id}", params: { data: { note: "hijacked" } },
        headers: auth_headers_for(owner), as: :json
      expect(response).to have_http_status(:forbidden)

      delete "/api/v1/collections/#{entry.entry_id}", headers: auth_headers_for(owner)
      expect(response).to have_http_status(:forbidden)

      expect(entry.reload.note).to eq("mine")
    end

    it "still lets the owner and the service write" do
      entry = create(:collection_entry, user: owner)

      patch "/api/v1/collections/#{entry.entry_id}", params: { data: { note: "owner" } },
        headers: auth_headers_for(owner), as: :json
      expect(response).to have_http_status(:ok)

      patch "/api/v1/collections/#{entry.entry_id}", params: { data: { note: "bot" } },
        headers: service_headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(entry.reload.note).to eq("bot")
    end
  end

  describe "owner updates cannot reassign a record" do
    {
      "collections" => [ :collection_entry, :entry_id, { note: "x" } ],
      "backlog" => [ :backlog_entry, :entry_id, { note: "x" } ],
      "completions" => [ :completion, :completion_id, { note: "x" } ],
      "favorites" => [ :favorite, :entry_id, { note: "x" } ],
      "reviews" => [ :review, :review_id, { title: "x" } ],
      "journal_entries" => [ :journal_entry, :entry_id, { entry_title: "x" } ]
    }.each do |path, (factory, pk, editable)|
      it "ignores user_id and the primary key on PATCH /api/v1/#{path}/:id" do
        record = create(factory, user: owner)
        original_pk = record.public_send(pk)

        patch "/api/v1/#{path}/#{original_pk}",
          params: { data: editable.merge(user_id: victim.user_id, pk => original_pk + 1_000_000) },
          headers: auth_headers_for(owner), as: :json

        expect(response).to have_http_status(:ok)
        reloaded = record.class.find(original_pk)
        expect(reloaded.user_id).to eq(owner.user_id)
        expect(reloaded.public_send(editable.keys.first)).to eq("x")
      end
    end

    it "ignores user_id on PATCH /api/v1/user_socials/:id" do
      social = create(:user_social, user: owner)

      patch "/api/v1/user_socials/#{social.id}",
        params: { data: { display_text: "x", user_id: victim.user_id } },
        headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:ok)
      expect(social.reload).to have_attributes(user_id: owner.user_id, display_text: "x")
    end

    it "ignores extra columns on owner creates" do
      post "/api/v1/users/#{owner.user_id}/backlog",
        params: { data: { gamedb_game_id: create(:game).game_id, entry_id: 1_999_999_999 } },
        headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:created)
      expect(json.dig("data", "entry_id")).not_to eq(1_999_999_999)
    end
  end

  describe "imports" do
    {
      "collection_csv_imports" => :collection_csv_import,
      "completionator_imports" => :completionator_import,
      "steam_collection_imports" => :steam_collection_import
    }.each do |path, factory|
      it "lets the owner set only status and current_index on PATCH /api/v1/#{path}/:id" do
        import = create(factory, user: owner)

        patch "/api/v1/#{path}/#{import.import_id}",
          params: { data: { status: "paused", current_index: 3, user_id: victim.user_id, test_mode: true } },
          headers: auth_headers_for(owner), as: :json

        expect(response).to have_http_status(:ok)
        expect(import.reload).to have_attributes(status: "paused", current_index: 3,
          user_id: owner.user_id, test_mode: false)
      end
    end

    {
      "collection_csv_import_items" => :collection_csv_import_item,
      "completionator_import_items" => :completionator_import_item,
      "steam_collection_import_items" => :steam_collection_import_item
    }.each do |path, factory|
      it "makes PATCH /api/v1/#{path}/:id service-only and limited to item result fields" do
        import = create(factory.to_s.delete_suffix("_item").to_sym, user: owner)
        item = create(factory, import: import)

        patch "/api/v1/#{path}/#{item.item_id}", params: { data: { status: "skipped" } },
          headers: auth_headers_for(owner), as: :json
        expect(response).to have_http_status(:forbidden)

        patch "/api/v1/#{path}/#{item.item_id}",
          params: { data: { status: "skipped", error_text: "bot", import_id: import.import_id + 1, row_index: 999 } },
          headers: service_headers, as: :json
        expect(response).to have_http_status(:ok)
        expect(item.reload).to have_attributes(status: "skipped", error_text: "bot",
          import_id: import.import_id)
        expect(item.row_index).not_to eq(999)
      end
    end
  end

  describe "bot-community data" do
    def expect_member_blocked_and_admin_allowed(method, path, payload = nil)
      send(method, path, params: payload, headers: auth_headers_for(owner), as: :json)
      expect(response).to have_http_status(:forbidden), "member #{method.upcase} #{path}"

      send(method, path, params: payload, headers: auth_headers_for(admin), as: :json)
      expect(response).not_to have_http_status(:forbidden), "admin #{method.upcase} #{path}"
    end

    it "guards RSS feed writes" do
      expect_member_blocked_and_admin_allowed(:post, "/api/v1/rss_feeds",
        { data: { feed_name: "f #{SecureRandom.hex(3)}", feed_url: "https://e.test/#{SecureRandom.hex(4)}.rss",
                  channel_id: "1" } })
      feed = create(:rss_feed)
      expect_member_blocked_and_admin_allowed(:patch, "/api/v1/rss_feeds/#{feed.feed_id}", { data: { feed_name: "n" } })
      expect_member_blocked_and_admin_allowed(:delete, "/api/v1/rss_feeds/#{feed.feed_id}")
    end

    it "makes RSS seen-item writes service-only" do
      feed = create(:rss_feed)
      payload = { data: [ { item_id_hash: SecureRandom.hex(8) } ] }

      post "/api/v1/rss_feeds/#{feed.feed_id}/items", params: payload, headers: auth_headers_for(admin), as: :json
      expect(response).to have_http_status(:forbidden)

      post "/api/v1/rss_feeds/#{feed.feed_id}/items", params: payload, headers: service_headers, as: :json
      expect(response).to have_http_status(:created)
    end

    it "guards starboard writes" do
      entry = create(:starboard_entry)
      expect_member_blocked_and_admin_allowed(:patch, "/api/v1/starboard/#{entry.message_id}", { data: { star_count: 5 } })
      expect_member_blocked_and_admin_allowed(:delete, "/api/v1/starboard/#{entry.message_id}")
    end

    it "guards public reminder writes" do
      reminder = create(:public_reminder)
      expect_member_blocked_and_admin_allowed(:patch, "/api/v1/public_reminders/#{reminder.reminder_id}",
        { data: { message: "n" } })
      expect_member_blocked_and_admin_allowed(:delete, "/api/v1/public_reminders/#{reminder.reminder_id}")
    end

    it "guards suggestion writes" do
      expect_member_blocked_and_admin_allowed(:post, "/api/v1/suggestions",
        { data: { title: "t", created_by: owner.user_id, created_by_name: "n" } })
      expect_member_blocked_and_admin_allowed(:delete, "/api/v1/suggestions/#{create(:suggestion).suggestion_id}")
    end

    it "guards legacy voting info writes" do
      info = create(:voting_info)
      expect_member_blocked_and_admin_allowed(:patch, "/api/v1/voting_info/#{info.round_number}",
        { data: { next_vote_at: 3.days.from_now } })
      expect_member_blocked_and_admin_allowed(:delete, "/api/v1/voting_info/#{info.round_number}")
    end
  end
end
