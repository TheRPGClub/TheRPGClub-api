# frozen_string_literal: true

# A member's ordered shelf list (Now Playing, Backlog, Favorites; spec api#451
# story 15): every payload carries `sort_order`, and a PATCH with `position`
# moves one entry in a single request, renumbering the list server-side.
#
# The including spec defines `owner`, `other_user`, `factory` (the entry
# factory), `list_path` (the owner's list) and `entry_path(entry)`.
RSpec.shared_examples "a reorderable shelf list" do
  def list_ids
    get list_path, headers: auth_headers_for(owner)
    json.fetch("data").map { |e| e.fetch("entry_id") }
  end

  def move(entry, position, headers: auth_headers_for(owner))
    patch entry_path(entry), params: { data: { position: } }, headers:, as: :json
  end

  describe "sort_order in payloads" do
    it "is on every list entry and on show" do
      entry = create(factory, user: owner, sort_order: 3)

      get list_path, headers: auth_headers_for(other_user)
      expect(json.dig("data", 0, "sort_order")).to eq(3)

      get entry_path(entry), headers: auth_headers_for(other_user)
      expect(json.dig("data", "sort_order")).to eq(3)
    end

    it "is accepted on PATCH and echoed back" do
      entry = create(factory, user: owner, sort_order: 1)

      patch entry_path(entry), params: { data: { sort_order: 7 } }, headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "sort_order")).to eq(7)
      expect(entry.reload.sort_order).to eq(7)
    end
  end

  describe "PATCH with position" do
    let!(:entries) { Array.new(4) { |i| create(factory, user: owner, sort_order: i + 1) } }
    let!(:others_entry) { create(factory, user: other_user, sort_order: 2) }

    it "moves the entry down and renumbers the list 1..n" do
      move(entries[0], 3)

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "sort_order")).to eq(3)
      expect(list_ids).to eq([ entries[1], entries[2], entries[0], entries[3] ].map(&:entry_id))
      expect(json.fetch("data").map { |e| e.fetch("sort_order") }).to eq([ 1, 2, 3, 4 ])
    end

    it "moves the entry up" do
      move(entries[3], 1)

      expect(response).to have_http_status(:ok)
      expect(list_ids).to eq([ entries[3], entries[0], entries[1], entries[2] ].map(&:entry_id))
    end

    it "clamps a position past the end to last" do
      move(entries[1], 99)

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "sort_order")).to eq(4)
      expect(list_ids.last).to eq(entries[1].entry_id)
    end

    it "normalises null and duplicate sort_orders in display order" do
      entries[1].update_columns(sort_order: 1)
      entries[2].update_columns(sort_order: nil)
      entries[3].update_columns(sort_order: nil)
      before = list_ids

      move(entries[0], 2)

      expect(response).to have_http_status(:ok)
      expected = before - [ entries[0].entry_id ]
      expected.insert(1, entries[0].entry_id)
      expect(list_ids).to eq(expected)
      expect(json.fetch("data").map { |e| e.fetch("sort_order") }).to eq([ 1, 2, 3, 4 ])
    end

    it "leaves other members' lists alone" do
      move(entries[0], 4)

      expect(others_entry.reload.sort_order).to eq(2)
    end

    it "applies other fields in the same request" do
      patch entry_path(entries[2]), params: { data: { position: 1, note: "first now" } },
        headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("note" => "first now", "sort_order" => 1)
    end

    it "422s invalid_position for a non-positive or non-integer position" do
      [ 0, -1, "two", 1.5 ].each do |bad|
        move(entries[0], bad)

        expect(response).to have_http_status(:unprocessable_content)
        expect(json.fetch("error")).to eq("invalid_position")
      end
      expect(entries.map { |e| e.reload.sort_order }).to eq([ 1, 2, 3, 4 ])
    end

    it "422s invalid_position when sent with sort_order" do
      patch entry_path(entries[0]), params: { data: { position: 2, sort_order: 2 } },
        headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("error")).to eq("invalid_position")
    end

    it "locks the member's whole list before it writes the entry (no deadlock between two moves)" do
      statements = []
      track = ->(*, payload) { statements << payload[:sql] if payload[:sql].match?(/\A\s*(SELECT|UPDATE)/i) }
      ActiveSupport::Notifications.subscribed(track, "sql.active_record") do
        patch entry_path(entries[2]), params: { data: { position: 1, note: "locked first" } },
          headers: auth_headers_for(owner), as: :json
      end

      expect(response).to have_http_status(:ok)
      first_lock = statements.index { |sql| sql.include?("FOR UPDATE") }
      first_write = statements.index { |sql| sql.match?(/\A\s*UPDATE/i) }
      expect(first_lock).not_to be_nil
      expect(first_lock).to be < first_write
    end

    it "404s an unknown entry even with a bad position" do
      patch entry_path(entries[0]).sub(/\d+\z/, "999999999"), params: { data: { position: 0 } },
        headers: service_headers, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it "forbids a non-owner" do
      move(entries[0], 4, headers: auth_headers_for(other_user))

      expect(response).to have_http_status(:forbidden)
      expect(entries[0].reload.sort_order).to eq(1)
    end
  end
end
