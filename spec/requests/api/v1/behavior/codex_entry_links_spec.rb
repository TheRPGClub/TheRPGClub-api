# frozen_string_literal: true

require "rails_helper"

# "See also" links between Club Codex entries (spec #397, ticket #409):
# PUT /api/v1/codex/entries/:id/links replaces an entry's links; a link
# belongs to both entries and shows on both.
RSpec.describe "api/v1/codex/entries/:id/links behavior", type: :request do
  let(:regular) { create(:user, role_member: true, role_regular: true) }
  let(:other_regular) { create(:user, role_member: true, role_regular: true) }
  let(:member) { create(:user, role_member: true) }
  let(:admin) { create(:user, role_member: true, role_admin: true) }

  let(:lore_entry) { create(:codex_entry, :lore_entry, author: regular, title: "The #general wipe") }
  let(:history_event) { create(:codex_entry, :history_event, author: admin, title: "The club moves to Discord") }

  def put_links(entry, ids, as:)
    put "/api/v1/codex/entries/#{entry.id}/links", params: { data: { entry_ids: ids } },
      headers: auth_headers_for(as), as: :json
  end

  def links_of(entry, as: member)
    get "/api/v1/codex/#{entry.part.pluralize}/#{entry.id}", headers: as && auth_headers_for(as)
    expect(response).to have_http_status(:ok)
    json.dig("data", "links")
  end

  describe "linking entries" do
    it "shows a link set from one entry on both" do
      put_links(lore_entry, [ history_event.id ], as: regular)

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "links")).to eq(
        [ { "id" => history_event.id, "part" => "history_event", "title" => "The club moves to Discord" } ]
      )
      expect(links_of(history_event)).to eq(
        [ { "id" => lore_entry.id, "part" => "lore_entry", "title" => "The #general wipe" } ]
      )
      expect(links_of(lore_entry).map { |link| link["id"] }).to eq([ history_event.id ])
    end

    it "refuses a self-link" do
      put_links(lore_entry, [ lore_entry.id ], as: regular)

      expect(response).to have_http_status(:unprocessable_content)
      expect(json).to eq("error" => "invalid_links", "message" => "An entry can't link to itself.")
      expect(links_of(lore_entry)).to eq([])
    end

    it "refuses an unknown entry, and ids that aren't entry ids, changing nothing" do
      put_links(lore_entry, [ history_event.id ], as: regular)

      put_links(lore_entry, [ history_event.id, 999_999 ], as: regular)
      expect(response).to have_http_status(:unprocessable_content)
      expect(json).to eq("error" => "invalid_links", "message" => "No Club Codex entry 999999.")

      [ "abc", nil, { "id" => 1 } ].each do |ids|
        put_links(lore_entry, ids, as: regular)
        expect(response).to have_http_status(:unprocessable_content)
        expect(json.fetch("message")).to eq("entry_ids must be a list of entry ids.")
      end

      expect(links_of(lore_entry).map { |link| link["id"] }).to eq([ history_event.id ])
    end

    it "keeps one link per pair, whichever side sets it" do
      put_links(lore_entry, [ history_event.id, history_event.id ], as: regular)
      put_links(history_event, [ lore_entry.id ], as: admin)

      expect(response).to have_http_status(:ok)
      expect(links_of(lore_entry).map { |link| link["id"] }).to eq([ history_event.id ])
      expect(links_of(history_event).map { |link| link["id"] }).to eq([ lore_entry.id ])
    end

    it "shows a Fun Fact by its opening words, with mentioned members by name" do
      rhea = create(:user, role_member: true, global_name: "Rhea")
      fun_fact = create(:codex_entry, author: regular,
        body: "<@#{rhea.user_id}> once renamed every channel in the server to a different flavour of soup, " \
              "and nobody noticed for a week.")
      short = create(:codex_entry, author: regular, body: "Short and <@123456789> sweet.")

      put_links(lore_entry, [ fun_fact.id, short.id ], as: regular)

      expect(json.dig("data", "links")).to eq([
        { "id" => fun_fact.id, "part" => "fun_fact",
          "title" => "@Rhea once renamed every channel in the server to a…" },
        { "id" => short.id, "part" => "fun_fact", "title" => "Short and <@123456789> sweet." }
      ])
    end

    it "refuses a member who can't edit the entry" do
      put_links(lore_entry, [ history_event.id ], as: other_regular)
      expect(response).to have_http_status(:forbidden)
      expect(json).to eq("error" => "forbidden", "message" => "Only its author or a Moderator can edit this.")

      put_links(history_event, [ lore_entry.id ], as: regular)
      expect(response).to have_http_status(:forbidden)
      expect(json).to eq("error" => "forbidden", "message" => "Only Admins can change Club History.")

      expect(links_of(lore_entry)).to eq([])
    end

    it "needs a sign-in" do
      put "/api/v1/codex/entries/#{lore_entry.id}/links", params: { data: { entry_ids: [] } }, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it "is not found for a missing entry" do
      put "/api/v1/codex/entries/999999/links", params: { data: { entry_ids: [] } },
        headers: auth_headers_for(regular), as: :json

      expect(response).to have_http_status(:not_found)
    end

    it "links for the member the bot names, and refuses without one" do
      put "/api/v1/codex/entries/#{lore_entry.id}/links",
        params: { data: { entry_ids: [ history_event.id ], acting_user_id: regular.user_id } },
        headers: service_headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "links").map { |link| link["id"] }).to eq([ history_event.id ])

      put "/api/v1/codex/entries/#{lore_entry.id}/links", params: { data: { entry_ids: [] } },
        headers: service_headers, as: :json
      expect(response).to have_http_status(:bad_request)

      put "/api/v1/codex/entries/#{lore_entry.id}/links",
        params: { data: { entry_ids: [], acting_user_id: other_regular.user_id } },
        headers: service_headers, as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it "is hidden by the feature gate" do
      set_feature_flag("club_codex", "off")
      put_links(lore_entry, [ history_event.id ], as: regular)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "removing links" do
    let(:fun_fact) { create(:codex_entry, author: other_regular, body: "The bot has a favourite member.") }

    before do
      put_links(lore_entry, [ history_event.id, fun_fact.id ], as: regular)
    end

    it "removes a link from both sides when either side drops it" do
      put_links(lore_entry, [ fun_fact.id ], as: regular)

      expect(json.dig("data", "links").map { |link| link["id"] }).to eq([ fun_fact.id ])
      expect(links_of(history_event)).to eq([])

      put_links(fun_fact, [], as: other_regular)

      expect(response).to have_http_status(:ok)
      expect(links_of(fun_fact)).to eq([])
      expect(links_of(lore_entry)).to eq([])
    end

    it "lets an Admin drop a History Event's link to a Lore Entry they didn't write" do
      put_links(history_event, [], as: admin)

      expect(response).to have_http_status(:ok)
      expect(links_of(lore_entry).map { |link| link["id"] }).to eq([ fun_fact.id ])
    end

    it "removes an entry's links when it is deleted" do
      delete "/api/v1/codex/lore_entries/#{lore_entry.id}", headers: auth_headers_for(regular)
      expect(response).to have_http_status(:ok)

      expect(links_of(history_event)).to eq([])
      expect(links_of(fun_fact)).to eq([])
    end
  end

  describe "reading links" do
    let(:other_event) { create(:codex_entry, :history_event, author: admin, title: "The club is founded") }
    let(:fun_fact) { create(:codex_entry, author: regular, body: "The bot has a favourite member.") }

    before do
      put_links(history_event, [ lore_entry.id, other_event.id, fun_fact.id ], as: admin)
    end

    it "shows a signed-out reader of a History Event only its History Event links" do
      expect(links_of(history_event, as: nil)).to eq(
        [ { "id" => other_event.id, "part" => "history_event", "title" => "The club is founded" } ]
      )

      get "/api/v1/codex/history_events"
      expect(json.fetch("data").to_h { |entry| [ entry["id"], entry["links"].map { |link| link["id"] } ] })
        .to eq(history_event.id => [ other_event.id ], other_event.id => [ history_event.id ])
    end

    it "shows members every link, in lists and on the draw" do
      expect(links_of(history_event).map { |link| link["id"] }).to eq([ lore_entry.id, other_event.id, fun_fact.id ])

      get "/api/v1/codex/fun_facts", headers: auth_headers_for(member)
      expect(json.dig("data", 0, "links").map { |link| link["id"] }).to eq([ history_event.id ])

      get "/api/v1/codex/lore_entries", params: { acting_user_id: member.user_id }, headers: service_headers
      expect(json.dig("data", 0, "links").map { |link| link["id"] }).to eq([ history_event.id ])

      post "/api/v1/codex/fun_facts/draw", headers: auth_headers_for(member), as: :json
      expect(json.dig("fun_fact", "links").map { |link| link["id"] }).to eq([ history_event.id ])
    end
  end
end
