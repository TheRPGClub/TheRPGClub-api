# frozen_string_literal: true

require "rails_helper"

# The Club Codex (spec #397, ticket #404): the club_codex Feature, and Fun
# Facts under /api/v1/codex/fun_facts. Regulars and above add them; the
# author or a Moderator and above edits or deletes one; members read them,
# with each mentioned member under their current name.
RSpec.describe "api/v1/codex/fun_facts behavior", type: :request do
  let(:regular) { create(:user, role_member: true, role_regular: true, global_name: "Rhea") }
  let(:member) { create(:user, role_member: true) }
  let(:moderator) { create(:user, role_member: true, role_moderator: true) }

  def add_fun_fact(as:, body: "The club was nearly called The JRPG Club.")
    post "/api/v1/codex/fun_facts", params: { data: { body: body } }, headers: auth_headers_for(as), as: :json
  end

  describe "the Club Codex Feature" do
    it "is a hideable Feature that reads as Preview with no stored state", feature_flags: :none do
      admin = create(:user, role_admin: true)

      get "/api/v1/features", headers: auth_headers_for(admin)

      club_codex = json.fetch("data").find { |feature| feature["key"] == "club_codex" }
      expect(club_codex).to include("name" => "Club Codex", "state" => "preview", "core" => false,
        "hideable" => true, "last_change" => nil,
        "coverage" => { "website" => [ "Codex" ], "bot" => [ "/codex", "/funfact" ], "posts" => [ "Daily Fun Fact" ] })
    end
  end

  describe "adding a Fun Fact" do
    it "lets a Regular add one, published at once and credited to them" do
      add_fun_fact(as: regular)

      expect(response).to have_http_status(:created)
      expect(json.fetch("data")).to include(
        "part" => "fun_fact", "title" => nil, "rich_body" => nil,
        "body" => "The club was nearly called The JRPG Club.", "occurred_on" => nil, "date_precision" => nil,
        "kind" => nil, "mentions" => {}, "images" => [], "links" => [],
        "viewer" => { "can_edit" => true, "can_delete" => true },
        "author" => { "user_id" => regular.user_id, "name" => "Rhea",
                      "discord_avatar" => regular.discord_avatar, "avatar_url" => "/api/v1/users/#{regular.user_id}/avatar" }
      )

      get "/api/v1/codex/fun_facts/#{json.dig('data', 'id')}", headers: auth_headers_for(member)
      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "body")).to eq("The club was nearly called The JRPG Club.")
    end

    it "lets a Moderator, an Admin and a Superadmin add one without the Regulars role" do
      admin = create(:user, role_member: true, role_admin: true)

      add_fun_fact(as: moderator)
      expect(response).to have_http_status(:created)

      add_fun_fact(as: admin)
      expect(response).to have_http_status(:created)

      post "/api/v1/codex/fun_facts", params: { data: { body: "Superadmins too." } },
        headers: auth_headers_for(member, is_dev: true), as: :json
      expect(response).to have_http_status(:created)
    end

    it "tells a member without the Regulars role that they need it" do
      add_fun_fact(as: member)

      expect(response).to have_http_status(:forbidden)
      expect(json).to include("error" => "forbidden",
        "message" => "You need the Regulars role to add to the Club Codex.")
    end

    it "adds one for the member the bot names, from their stored roles" do
      post "/api/v1/codex/fun_facts", params: { data: { body: "From Discord.", acting_user_id: regular.user_id } },
        headers: service_headers, as: :json
      expect(response).to have_http_status(:created)
      expect(json.dig("data", "author", "user_id")).to eq(regular.user_id)
      expect(json.dig("data", "viewer")).to eq("can_edit" => true, "can_delete" => true)

      post "/api/v1/codex/fun_facts", params: { data: { body: "From Discord.", acting_user_id: member.user_id } },
        headers: service_headers, as: :json
      expect(response).to have_http_status(:forbidden)

      post "/api/v1/codex/fun_facts", params: { data: { body: "From Discord." } }, headers: service_headers, as: :json
      expect(response).to have_http_status(:bad_request)
    end

    it "needs a body of at most 300 characters, mention tokens included" do
      mentioned = create(:user, user_id: "123456789012345678")
      token = "<@#{mentioned.user_id}>"

      add_fun_fact(as: regular, body: "  ")
      expect(response).to have_http_status(:unprocessable_content)
      expect(json).to include("error" => "invalid_entry", "message" => "Body can't be blank")

      add_fun_fact(as: regular, body: nil)
      expect(response).to have_http_status(:unprocessable_content)

      add_fun_fact(as: regular, body: "#{token} #{'a' * (300 - token.length - 1)}")
      expect(response).to have_http_status(:created)

      add_fun_fact(as: regular, body: "#{token} #{'a' * (300 - token.length)}")
      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("message")).to eq("Body is too long (maximum is 300 characters)")
    end

    it "refuses a body holding a NUL character, which Postgres can't store" do
      add_fun_fact(as: regular, body: "a\u0000b")

      expect(response).to have_http_status(:unprocessable_content)
      expect(json).to eq("error" => "invalid_entry", "message" => "body can't hold NUL characters")
    end

    it "refuses a field a Fun Fact doesn't take, rather than dropping it" do
      %w[title rich_body occurred_on date_precision kind].each do |field|
        post "/api/v1/codex/fun_facts", params: { data: { body: "A Fun Fact.", field => "x" } },
          headers: auth_headers_for(regular), as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(json).to eq("error" => "invalid_entry", "message" => "A Fun Fact doesn't take #{field}")
      end
      expect(CodexEntry.count).to eq(0)
    end
  end

  describe "editing and deleting a Fun Fact" do
    let(:other_regular) { create(:user, role_member: true, role_regular: true) }
    let!(:fun_fact) { create(:codex_entry, :fun_fact, author: regular, body: "Rhea named the bot.") }

    def edit(as:, body: "Rhea named the bot, twice.")
      patch "/api/v1/codex/fun_facts/#{fun_fact.id}", params: { data: { body: body } }, headers: auth_headers_for(as),
        as: :json
    end

    def delete_it(as:)
      delete "/api/v1/codex/fun_facts/#{fun_fact.id}", headers: auth_headers_for(as)
    end

    it "lets the author edit and delete their own" do
      edit(as: regular)
      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "body")).to eq("Rhea named the bot, twice.")

      delete_it(as: regular)
      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to eq("id" => fun_fact.id, "deleted" => true)

      get "/api/v1/codex/fun_facts/#{fun_fact.id}", headers: auth_headers_for(regular)
      expect(response).to have_http_status(:not_found)
    end

    it "refuses another Regular" do
      edit(as: other_regular)
      expect(response).to have_http_status(:forbidden)
      expect(json.fetch("message")).to eq("Only its author or a Moderator can edit this.")

      delete_it(as: other_regular)
      expect(response).to have_http_status(:forbidden)
      expect(json.fetch("message")).to eq("Only its author or a Moderator can delete this.")

      get "/api/v1/codex/fun_facts/#{fun_fact.id}", headers: auth_headers_for(regular)
      expect(json.dig("data", "body")).to eq("Rhea named the bot.")
    end

    it "lets a Moderator edit and delete anyone's" do
      edit(as: moderator)
      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "author", "user_id")).to eq(regular.user_id)

      delete_it(as: moderator)
      expect(response).to have_http_status(:ok)
    end

    it "gives a mentioned member no extra rights" do
      fun_fact.update!(body: "<@#{other_regular.user_id}> was the first Regular.")

      get "/api/v1/codex/fun_facts/#{fun_fact.id}", headers: auth_headers_for(other_regular)
      expect(json.dig("data", "viewer")).to eq("can_edit" => false, "can_delete" => false)

      edit(as: other_regular)
      expect(response).to have_http_status(:forbidden)

      delete_it(as: other_regular)
      expect(response).to have_http_status(:forbidden)
    end

    it "edits and deletes for the member the bot names" do
      patch "/api/v1/codex/fun_facts/#{fun_fact.id}",
        params: { data: { body: "Edited from Discord.", acting_user_id: other_regular.user_id } },
        headers: service_headers, as: :json
      expect(response).to have_http_status(:forbidden)

      patch "/api/v1/codex/fun_facts/#{fun_fact.id}",
        params: { data: { body: "Edited from Discord.", acting_user_id: regular.user_id } },
        headers: service_headers, as: :json
      expect(response).to have_http_status(:ok)

      delete "/api/v1/codex/fun_facts/#{fun_fact.id}", headers: service_headers
      expect(response).to have_http_status(:bad_request)

      delete "/api/v1/codex/fun_facts/#{fun_fact.id}", params: { acting_user_id: other_regular.user_id },
        headers: service_headers
      expect(response).to have_http_status(:forbidden)

      delete "/api/v1/codex/fun_facts/#{fun_fact.id}", params: { acting_user_id: regular.user_id },
        headers: service_headers
      expect(response).to have_http_status(:ok)
    end

    it "keeps the 300-character limit on edit" do
      edit(as: regular, body: "a" * 301)

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("error")).to eq("invalid_entry")
    end

    it "refuses a field a Fun Fact doesn't take on edit, changing nothing" do
      patch "/api/v1/codex/fun_facts/#{fun_fact.id}", params: { data: { body: "Edited.", title: "A title" } },
        headers: auth_headers_for(regular), as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json).to eq("error" => "invalid_entry", "message" => "A Fun Fact doesn't take title")
      expect(fun_fact.reload.body).not_to eq("Edited.")
    end
  end

  describe "the viewer flags" do
    let!(:fun_fact) { create(:codex_entry, :fun_fact, author: regular) }

    def viewer_for(headers, params = {})
      get "/api/v1/codex/fun_facts/#{fun_fact.id}", params: params, headers: headers
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

  describe "listing Fun Facts" do
    it "lists them newest first, paginated, with each one's viewer flags" do
      older = create(:codex_entry, :fun_fact, author: regular, body: "Older.", created_at: 2.days.ago)
      newer = create(:codex_entry, :fun_fact, author: member, body: "Newer.", created_at: 1.day.ago)
      create(:codex_entry, :fun_fact, author: member, body: "Newest.")

      get "/api/v1/codex/fun_facts", params: { per: 2, page: 2 }, headers: auth_headers_for(regular)
      expect(response).to have_http_status(:ok)
      expect(json.fetch("data").map { |entry| entry["id"] }).to eq([ older.id ])
      expect(json.fetch("meta")).to include("page" => 2, "pages" => 2, "count" => 3, "per" => 2)

      get "/api/v1/codex/fun_facts", headers: auth_headers_for(regular)
      expect(json.fetch("data").map { |entry| entry["body"] }).to eq(%w[Newest. Newer. Older.])
      expect(json.fetch("data").map { |entry| entry.dig("viewer", "can_edit") }).to eq([ false, false, true ])
      expect(json.fetch("data").second.dig("author", "user_id")).to eq(newer.author_user_id)
    end

    it "refuses a signed-out visitor" do
      get "/api/v1/codex/fun_facts"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "mentions" do
    let(:ada) { create(:user, user_id: "111111111111111111", global_name: "Ada") }
    let(:bo) { create(:user, user_id: "222222222222222222", username: "bo", global_name: nil) }

    it "pulls mentioned members out of the body, ignoring unknown ids and keeping the token text" do
      add_fun_fact(as: regular, body: "<@#{ada.user_id}> and <@!#{bo.user_id}> met <@999999999999999999>.")

      expect(json.dig("data", "body")).to eq("<@#{ada.user_id}> and <@!#{bo.user_id}> met <@999999999999999999>.")
      expect(json.dig("data", "mentions")).to eq(
        ada.user_id => { "user_id" => ada.user_id, "name" => "Ada", "discord_avatar" => ada.discord_avatar, "avatar_url" => "/api/v1/users/#{ada.user_id}/avatar" },
        bo.user_id => { "user_id" => bo.user_id, "name" => "bo", "discord_avatar" => bo.discord_avatar, "avatar_url" => "/api/v1/users/#{bo.user_id}/avatar" }
      )
    end

    it "pulls them again on edit" do
      add_fun_fact(as: regular, body: "<@#{ada.user_id}> joined first.")
      id = json.dig("data", "id")

      patch "/api/v1/codex/fun_facts/#{id}", params: { data: { body: "<@#{bo.user_id}> joined first." } },
        headers: auth_headers_for(regular), as: :json

      expect(json.dig("data", "mentions").keys).to eq([ bo.user_id ])
      get "/api/v1/codex/fun_facts", headers: auth_headers_for(member)
      expect(json.dig("data", 0, "mentions").keys).to eq([ bo.user_id ])
    end

    it "shows a renamed member under their new name" do
      add_fun_fact(as: regular, body: "<@#{ada.user_id}> brought snacks.")
      id = json.dig("data", "id")

      ada.update!(global_name: "Ada Lovelace")
      regular.update!(global_name: "Rhea Silvia")

      get "/api/v1/codex/fun_facts/#{id}", headers: auth_headers_for(member)
      expect(json.dig("data", "mentions", ada.user_id, "name")).to eq("Ada Lovelace")
      expect(json.dig("data", "author", "name")).to eq("Rhea Silvia")
    end

    it "goes with the Fun Fact when it is deleted" do
      add_fun_fact(as: regular, body: "<@#{ada.user_id}> brought snacks.")

      expect { delete "/api/v1/codex/fun_facts/#{json.dig('data', 'id')}", headers: auth_headers_for(regular) }
        .to change(CodexEntryMention, :count).by(-1)
    end
  end

  describe "the feature gate" do
    # Each call reads, adds, edits and deletes, on a Fun Fact of its own.
    def every_endpoint(headers, data = {})
      fun_fact = create(:codex_entry, :fun_fact, author: regular)
      get "/api/v1/codex/fun_facts", params: data.slice(:acting_user_id), headers: headers
      statuses = [ response.status ]
      get "/api/v1/codex/fun_facts/#{fun_fact.id}", params: data.slice(:acting_user_id), headers: headers
      statuses << response.status
      post "/api/v1/codex/fun_facts", params: { data: data.merge(body: "New.") }, headers: headers, as: :json
      statuses << response.status
      patch "/api/v1/codex/fun_facts/#{fun_fact.id}", params: { data: data.merge(body: "Edited.") }, headers: headers,
        as: :json
      statuses << response.status
      delete "/api/v1/codex/fun_facts/#{fun_fact.id}", params: data.slice(:acting_user_id), headers: headers
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
      expect(every_endpoint(auth_headers_for(member, is_dev: true))).to all(eq(404))
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
