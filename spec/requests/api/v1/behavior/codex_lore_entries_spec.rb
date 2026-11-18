# frozen_string_literal: true

require "rails_helper"

# Club Lore (spec #397, ticket #407): Lore Entries under
# /api/v1/codex/lore_entries. Regulars and above publish a Lore Entry, a
# story with a title and an optional date; the author or a Moderator and
# above edits or deletes one; members read them newest first.
RSpec.describe "api/v1/codex/lore_entries behavior", type: :request do
  let(:regular) { create(:user, role_member: true, role_regular: true, global_name: "Rhea") }
  let(:member) { create(:user, role_member: true) }
  let(:moderator) { create(:user, role_member: true, role_moderator: true) }
  # A Plate.js story as the website's editor saves it.
  let(:story) do
    [ { "type" => "h2", "children" => [ { "text" => "The wipe" } ] },
      { "type" => "p", "children" => [ { "text" => "Nobody knows who ran it.", "bold" => true } ] } ]
  end

  def add_lore_entry(as:, **data)
    data = { title: "The #general wipe", rich_body: story, body: "## The wipe\n**Nobody knows who ran it.**" }
      .merge(data)
    post "/api/v1/codex/lore_entries", params: { data: data }, headers: auth_headers_for(as), as: :json
  end

  describe "adding a Lore Entry" do
    it "lets a Regular add one, published at once and credited to them, its story unchanged" do
      add_lore_entry(as: regular)

      expect(response).to have_http_status(:created)
      expect(json.fetch("data")).to include(
        "part" => "lore_entry", "title" => "The #general wipe", "rich_body" => story,
        "body" => "## The wipe\n**Nobody knows who ran it.**", "occurred_on" => nil, "date_precision" => nil,
        "kind" => nil, "mentions" => {}, "images" => [], "links" => [],
        "viewer" => { "can_edit" => true, "can_delete" => true },
        "author" => { "user_id" => regular.user_id, "name" => "Rhea",
                      "avatar_url" => "/api/v1/users/#{regular.user_id}/avatar" }
      )

      get "/api/v1/codex/lore_entries/#{json.dig('data', 'id')}", headers: auth_headers_for(member)
      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "rich_body")).to eq(story)
      expect(json.dig("data", "viewer")).to eq("can_edit" => false, "can_delete" => false)
    end

    it "needs a title of at most 100 characters" do
      add_lore_entry(as: regular, title: nil)
      expect(response).to have_http_status(:unprocessable_content)
      expect(json).to include("error" => "invalid_entry", "message" => "Title can't be blank")

      add_lore_entry(as: regular, title: "   ")
      expect(response).to have_http_status(:unprocessable_content)

      add_lore_entry(as: regular, title: "a" * 101)
      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("message")).to eq("Title is too long (maximum is 100 characters)")

      add_lore_entry(as: regular, title: "  #{'a' * 100}  ")
      expect(response).to have_http_status(:created)
      expect(json.dig("data", "title")).to eq("a" * 100)
    end

    it "needs the story's Discord text" do
      add_lore_entry(as: regular, body: nil)
      expect(response).to have_http_status(:unprocessable_content)
      expect(json).to include("error" => "invalid_entry", "message" => "Body can't be blank")

      add_lore_entry(as: regular, rich_body: nil, body: " ")
      expect(response).to have_http_status(:unprocessable_content)

      add_lore_entry(as: regular, rich_body: nil, body: "Told in plain text.")
      expect(response).to have_http_status(:created)
    end

    it "refuses a field that should be text but isn't" do
      add_lore_entry(as: regular, title: { "text" => "The wipe" })

      expect(response).to have_http_status(:unprocessable_content)
      expect(json).to include("error" => "invalid_entry", "message" => "title must be text")
    end

    it "refuses a field a Lore Entry doesn't take, rather than dropping it" do
      add_lore_entry(as: regular, kind: "milestone")
      expect(response).to have_http_status(:unprocessable_content)
      expect(json).to eq("error" => "invalid_entry", "message" => "A Lore Entry doesn't take kind")

      add_lore_entry(as: regular, summary: "Not a field.")
      expect(response).to have_http_status(:unprocessable_content)
      expect(json).to eq("error" => "invalid_entry", "message" => "A Lore Entry doesn't take summary")
      expect(CodexEntry.count).to eq(0)
    end

    it "refuses a NUL character in the title or the story, which Postgres can't store" do
      add_lore_entry(as: regular, title: "The\u0000wipe")
      expect(response).to have_http_status(:unprocessable_content)
      expect(json).to eq("error" => "invalid_entry", "message" => "title can't hold NUL characters")

      add_lore_entry(as: regular, rich_body: [ { "type" => "p", "children" => [ { "text" => "a\u0000b" } ] } ])
      expect(response).to have_http_status(:unprocessable_content)
      expect(json).to eq("error" => "invalid_entry", "message" => "rich_body can't hold NUL characters")
      expect(CodexEntry.count).to eq(0)
    end
  end

  describe "dating a Lore Entry" do
    def dated(occurred_on, date_precision)
      add_lore_entry(as: regular, occurred_on: occurred_on, date_precision: date_precision)
      expect(response).to have_http_status(:created)
      id = json.dig("data", "id")
      get "/api/v1/codex/lore_entries/#{id}", headers: auth_headers_for(member)
      json.fetch("data").slice("occurred_on", "date_precision")
    end

    it "reads a month date back at month precision, on the first of the month" do
      expect(dated("2018-03-14", "month")).to eq("occurred_on" => "2018-03-01", "date_precision" => "month")
    end

    it "reads a year date back at year precision, on 1 January" do
      expect(dated("2016-07-04", "year")).to eq("occurred_on" => "2016-01-01", "date_precision" => "year")
    end

    it "keeps a full date as given" do
      expect(dated("2020-05-14", "day")).to eq("occurred_on" => "2020-05-14", "date_precision" => "day")
    end

    it "refuses a date without a precision, and a precision without a date" do
      add_lore_entry(as: regular, occurred_on: "2020-05-14")
      expect(response).to have_http_status(:unprocessable_content)
      expect(json).to include("error" => "invalid_entry", "message" => "Date precision can't be blank")

      add_lore_entry(as: regular, date_precision: "month")
      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("message")).to eq("Occurred on can't be blank")
    end

    it "refuses an unknown precision and a date that isn't one" do
      add_lore_entry(as: regular, occurred_on: "2020-05-14", date_precision: "decade")
      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("message")).to eq("Date precision must be one of day, month, year")

      [ "2020-02-30", "14 May 2020", "2020-05", "soon" ].each do |occurred_on|
        add_lore_entry(as: regular, occurred_on: occurred_on, date_precision: "day")
        expect(response).to have_http_status(:unprocessable_content)
        expect(json.fetch("message")).to eq("Occurred on must be a date (YYYY-MM-DD)")
      end
    end

    it "moves, changes and removes the date on edit" do
      add_lore_entry(as: regular, occurred_on: "2020-05-14", date_precision: "day")
      path = "/api/v1/codex/lore_entries/#{json.dig('data', 'id')}"

      patch path, params: { data: { date_precision: "year" } }, headers: auth_headers_for(regular), as: :json
      expect(json.fetch("data")).to include("occurred_on" => "2020-01-01", "date_precision" => "year")

      patch path, params: { data: { occurred_on: "2019-11-30", date_precision: "month" } },
        headers: auth_headers_for(regular), as: :json
      expect(json.fetch("data")).to include("occurred_on" => "2019-11-01", "date_precision" => "month")

      patch path, params: { data: { occurred_on: nil } }, headers: auth_headers_for(regular), as: :json
      expect(response).to have_http_status(:unprocessable_content)

      patch path, params: { data: { occurred_on: nil, date_precision: nil } }, headers: auth_headers_for(regular),
        as: :json
      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("occurred_on" => nil, "date_precision" => nil)
    end
  end

  describe "who may add, edit and delete" do
    let(:other_regular) { create(:user, role_member: true, role_regular: true) }
    let!(:lore_entry) { create(:codex_entry, :lore_entry, author: regular, title: "The bake-off") }
    let(:path) { "/api/v1/codex/lore_entries/#{lore_entry.id}" }

    def edit(as:, title: "The great bake-off")
      patch path, params: { data: { title: title } }, headers: auth_headers_for(as), as: :json
    end

    def delete_it(as:)
      delete path, headers: auth_headers_for(as)
    end

    it "lets a Moderator, an Admin and a Superadmin add one without the Regulars role" do
      add_lore_entry(as: moderator)
      expect(response).to have_http_status(:created)

      add_lore_entry(as: create(:user, role_member: true, role_admin: true))
      expect(response).to have_http_status(:created)

      post "/api/v1/codex/lore_entries", params: { data: { title: "From a Superadmin", body: "B" } },
        headers: auth_headers_for(member, is_dev: true), as: :json
      expect(response).to have_http_status(:created)
    end

    it "tells a member without the Regulars role that they need it" do
      add_lore_entry(as: member)

      expect(response).to have_http_status(:forbidden)
      expect(json).to include("error" => "forbidden",
        "message" => "You need the Regulars role to add to the Club Codex.")
    end

    it "lets the author edit and delete their own" do
      edit(as: regular)
      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "title")).to eq("The great bake-off")
      expect(json.dig("data", "body")).to eq(lore_entry.body)

      delete_it(as: regular)
      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to eq("id" => lore_entry.id, "deleted" => true)

      get path, headers: auth_headers_for(regular)
      expect(response).to have_http_status(:not_found)
    end

    it "refuses another Regular" do
      edit(as: other_regular)
      expect(response).to have_http_status(:forbidden)
      expect(json.fetch("message")).to eq("Only its author or a Moderator can edit this.")

      delete_it(as: other_regular)
      expect(response).to have_http_status(:forbidden)
      expect(json.fetch("message")).to eq("Only its author or a Moderator can delete this.")

      get path, headers: auth_headers_for(regular)
      expect(json.dig("data", "title")).to eq("The bake-off")
    end

    it "lets a Moderator edit and delete anyone's, keeping its author" do
      edit(as: moderator)
      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "author", "user_id")).to eq(regular.user_id)

      delete_it(as: moderator)
      expect(response).to have_http_status(:ok)
    end

    it "gives a mentioned member no extra rights" do
      lore_entry.update!(body: "<@#{other_regular.user_id}> baked the winning cake.")

      get path, headers: auth_headers_for(other_regular)
      expect(json.dig("data", "viewer")).to eq("can_edit" => false, "can_delete" => false)

      edit(as: other_regular)
      expect(response).to have_http_status(:forbidden)
    end

    it "keeps the title and body rules on edit" do
      edit(as: regular, title: "")
      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("message")).to eq("Title can't be blank")

      patch path, params: { data: { body: nil } }, headers: auth_headers_for(regular), as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("message")).to eq("Body can't be blank")
    end

    it "acts for the member the bot names, from their stored roles" do
      patch path, params: { data: { title: "From Discord", acting_user_id: other_regular.user_id } },
        headers: service_headers, as: :json
      expect(response).to have_http_status(:forbidden)

      patch path, params: { data: { title: "From Discord", acting_user_id: regular.user_id } },
        headers: service_headers, as: :json
      expect(response).to have_http_status(:ok)

      delete path, headers: service_headers
      expect(response).to have_http_status(:bad_request)

      delete path, params: { acting_user_id: regular.user_id }, headers: service_headers
      expect(response).to have_http_status(:ok)
    end

    it "is not reached through another part's path" do
      fun_fact = create(:codex_entry, :fun_fact, author: regular)

      get "/api/v1/codex/lore_entries/#{fun_fact.id}", headers: auth_headers_for(regular)
      expect(response).to have_http_status(:not_found)

      get "/api/v1/codex/fun_facts/#{lore_entry.id}", headers: auth_headers_for(regular)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "the viewer flags" do
    let!(:lore_entry) { create(:codex_entry, :lore_entry, author: regular) }

    def viewer_for(headers, params = {})
      get "/api/v1/codex/lore_entries/#{lore_entry.id}", params: params, headers: headers
      json.dig("data", "viewer")
    end

    it "match who may edit and delete" do
      yes = { "can_edit" => true, "can_delete" => true }
      no = { "can_edit" => false, "can_delete" => false }

      expect(viewer_for(auth_headers_for(regular))).to eq(yes)
      expect(viewer_for(auth_headers_for(moderator))).to eq(yes)
      expect(viewer_for(auth_headers_for(create(:user, role_admin: true)))).to eq(yes)
      expect(viewer_for(auth_headers_for(member, is_dev: true))).to eq(yes)
      expect(viewer_for(auth_headers_for(member))).to eq(no)
      expect(viewer_for(auth_headers_for(create(:user, role_member: true, role_regular: true)))).to eq(no)
      expect(viewer_for(service_headers, acting_user_id: regular.user_id)).to eq(yes)
      expect(viewer_for(service_headers, acting_user_id: member.user_id)).to eq(no)
      expect(viewer_for(service_headers)).to eq(no)
    end
  end

  describe "listing Lore Entries" do
    it "lists them newest first, paginated, without other parts" do
      older = create(:codex_entry, :lore_entry, author: regular, title: "Older", created_at: 2.days.ago)
      create(:codex_entry, :lore_entry, author: member, title: "Newer", created_at: 1.day.ago)
      create(:codex_entry, :lore_entry, author: member, title: "Newest")
      create(:codex_entry, :fun_fact, author: regular)

      get "/api/v1/codex/lore_entries", params: { per: 2, page: 2 }, headers: auth_headers_for(regular)
      expect(response).to have_http_status(:ok)
      expect(json.fetch("data").map { |entry| entry["id"] }).to eq([ older.id ])
      expect(json.fetch("meta")).to include("page" => 2, "pages" => 2, "count" => 3, "per" => 2)

      get "/api/v1/codex/lore_entries", headers: auth_headers_for(regular)
      expect(json.fetch("data").map { |entry| entry["title"] }).to eq(%w[Newest Newer Older])
      expect(json.fetch("data").map { |entry| entry.dig("viewer", "can_edit") }).to eq([ false, false, true ])
    end

    it "refuses a signed-out visitor" do
      lore_entry = create(:codex_entry, :lore_entry, author: regular)

      get "/api/v1/codex/lore_entries"
      expect(response).to have_http_status(:unauthorized)

      get "/api/v1/codex/lore_entries/#{lore_entry.id}"
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "mentions" do
    let(:ada) { create(:user, user_id: "111111111111111111", global_name: "Ada") }
    let(:bo) { create(:user, user_id: "222222222222222222", username: "bo", global_name: nil) }

    it "pulls mentioned members out of the body, ignoring unknown ids, and again on edit" do
      add_lore_entry(as: regular, body: "<@#{ada.user_id}> and <@!#{bo.user_id}> met <@999999999999999999>.")
      expect(json.dig("data", "mentions").keys).to contain_exactly(ada.user_id, bo.user_id)
      expect(json.dig("data", "mentions", ada.user_id)).to eq(
        "user_id" => ada.user_id, "name" => "Ada", "avatar_url" => "/api/v1/users/#{ada.user_id}/avatar"
      )

      patch "/api/v1/codex/lore_entries/#{json.dig('data', 'id')}",
        params: { data: { body: "<@#{bo.user_id}> told it first." } }, headers: auth_headers_for(regular), as: :json
      expect(json.dig("data", "mentions").keys).to eq([ bo.user_id ])

      get "/api/v1/codex/lore_entries", headers: auth_headers_for(member)
      expect(json.dig("data", 0, "mentions").keys).to eq([ bo.user_id ])
    end

    it "shows a renamed member under their new name" do
      add_lore_entry(as: regular, body: "<@#{ada.user_id}> ran the command.")
      id = json.dig("data", "id")

      ada.update!(global_name: "Ada Lovelace")

      get "/api/v1/codex/lore_entries/#{id}", headers: auth_headers_for(member)
      expect(json.dig("data", "mentions", ada.user_id, "name")).to eq("Ada Lovelace")
    end
  end

  describe "the feature gate" do
    # Each call reads, adds, edits and deletes, on a Lore Entry of its own.
    def every_endpoint(headers, data = {})
      lore_entry = create(:codex_entry, :lore_entry, author: regular)
      path = "/api/v1/codex/lore_entries/#{lore_entry.id}"
      get "/api/v1/codex/lore_entries", params: data.slice(:acting_user_id), headers: headers
      statuses = [ response.status ]
      get path, params: data.slice(:acting_user_id), headers: headers
      statuses << response.status
      post "/api/v1/codex/lore_entries", params: { data: data.merge(title: "New", body: "New.") }, headers: headers,
        as: :json
      statuses << response.status
      patch path, params: { data: data.merge(title: "Edited") }, headers: headers, as: :json
      statuses << response.status
      delete path, params: data.slice(:acting_user_id), headers: headers
      statuses << response.status
    end

    it "hides every endpoint from non-staff in Preview" do
      set_feature_flag("club_codex", "preview")

      expect(every_endpoint(auth_headers_for(regular))).to all(eq(404))
    end

    it "answers staff in Preview" do
      set_feature_flag("club_codex", "preview")

      expect(every_endpoint(auth_headers_for(create(:user, role_admin: true)))).to eq([ 200, 200, 201, 200, 200 ])
    end

    it "hides every endpoint from everyone when Off" do
      set_feature_flag("club_codex", "off")

      expect(every_endpoint(auth_headers_for(create(:user, role_admin: true)))).to all(eq(404))
    end

    it "lets the service token through, applying the Flag to the member it acts for" do
      set_feature_flag("club_codex", "preview")

      expect(every_endpoint(service_headers, acting_user_id: create(:user, role_admin: true).user_id))
        .to eq([ 200, 200, 201, 200, 200 ])

      reads_and_writes = every_endpoint(service_headers, acting_user_id: regular.user_id)
      expect(reads_and_writes.first(2)).to eq([ 200, 200 ])
      expect(reads_and_writes.last(3)).to all(eq(403))
    end
  end
end
