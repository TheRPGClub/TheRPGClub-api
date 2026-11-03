# frozen_string_literal: true

require "rails_helper"

# Behavior specs for the search-synonym group endpoints (#108): reads are open
# to any authenticated principal, writes (including the bulk terms delete) are
# admin/dev/service-gated. Deleting a group cascades to its terms.
RSpec.describe "api/v1/search_synonym_groups behavior", type: :request do
  describe "GET /api/v1/search_synonym_groups" do
    it "lists groups with the documented fields" do
      group = create(:search_synonym_group)
      create(:search_synonym, group: group, term_text: "GrpFind zk1")

      get "/api/v1/search_synonym_groups", params: { q: "grpfind zk1" }, headers: service_headers

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data").length).to eq(1)
      expect(json.fetch("data").first).to include(
        "group_id" => group.group_id,
        "created_by" => group.created_by
      )
      expect(json.fetch("meta")).to include("page" => 1, "count" => 1)
    end

    it "matches ?q= through the group's terms by normalised substring" do
      group = create(:search_synonym_group)
      create(:search_synonym, group: group, term_text: "Grand-Find zk2")
      other = create(:search_synonym_group)
      create(:search_synonym, group: other, term_text: "Suikoden zk3")

      get "/api/v1/search_synonym_groups", params: { q: "grandfind" }, headers: auth_headers_for(create(:user))

      ids = json.fetch("data").map { |g| g.fetch("group_id") }
      expect(ids).to eq([ group.group_id ])
    end

    it "embeds each group's terms, sorted by text, with ?include=terms" do
      group = create(:search_synonym_group)
      create(:search_synonym, group: group, term_text: "Zeta IncT1")
      create(:search_synonym, group: group, term_text: "Alpha IncT1")
      create(:search_synonym, term_text: "Other IncT1")

      get "/api/v1/search_synonym_groups", params: { q: "alpha inct1", include: "terms" },
        headers: auth_headers_for(create(:user))

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data").length).to eq(1)
      terms = json.dig("data", 0, "terms")
      expect(terms.map { |t| t.fetch("term_text") }).to eq([ "Alpha IncT1", "Zeta IncT1" ])
      expect(terms.first).to include("group_id" => group.group_id, "term_norm" => "alphainct1")
    end

    it "embeds an empty term list for a group with no terms" do
      group = create(:search_synonym_group)

      get "/api/v1/search_synonym_groups", params: { include: "terms", per: 500 }, headers: service_headers

      row = json.fetch("data").find { |g| g.fetch("group_id") == group.group_id }
      expect(row.fetch("terms")).to eq([])
    end

    it "leaves terms out without ?include=terms" do
      create(:search_synonym, term_text: "NoInc zk9")

      get "/api/v1/search_synonym_groups", params: { q: "noinc zk9" }, headers: service_headers

      expect(json.dig("data", 0)).not_to have_key("terms")
    end

    it "requires authentication" do
      get "/api/v1/search_synonym_groups"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/search_synonym_groups/:id" do
    it "shows a group to any authenticated user" do
      group = create(:search_synonym_group)

      get "/api/v1/search_synonym_groups/#{group.group_id}", headers: auth_headers_for(create(:user))

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("group_id" => group.group_id, "created_by" => group.created_by)
    end

    it "embeds the group's terms with ?include=terms" do
      group = create(:search_synonym_group)
      term = create(:search_synonym, group: group, term_text: "Show Term")

      get "/api/v1/search_synonym_groups/#{group.group_id}", params: { include: "terms" },
        headers: auth_headers_for(create(:user))

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "terms")).to eq([
        { "term_id" => term.term_id, "group_id" => group.group_id, "term_text" => "Show Term",
          "term_norm" => "showterm", "created_at" => term.reload.created_at.as_json, "created_by" => term.created_by }
      ])
    end

    it "404s for an unknown id" do
      get "/api/v1/search_synonym_groups/999999999", headers: service_headers

      expect(response).to have_http_status(:not_found)
      expect(json).to have_key("error")
    end
  end

  describe "POST /api/v1/search_synonym_groups" do
    let(:payload) { { data: { created_by: "1234" } } }

    it "creates a group as an admin" do
      expect {
        post "/api/v1/search_synonym_groups", params: payload,
          headers: auth_headers_for(create(:user, :admin)), as: :json
      }.to change(GamedbSearchSynonymGroup, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(json.fetch("data")).to include("created_by" => "1234")
      expect(json.dig("data", "group_id")).to be_a(Integer)
    end

    it "allows the service" do
      post "/api/v1/search_synonym_groups", params: payload, headers: service_headers, as: :json

      expect(response).to have_http_status(:created)
    end

    it "forbids a regular user" do
      expect {
        post "/api/v1/search_synonym_groups", params: payload, headers: auth_headers_for(create(:user)), as: :json
      }.not_to change(GamedbSearchSynonymGroup, :count)

      expect(response).to have_http_status(:forbidden)
      expect(json).to eq("error" => "forbidden")
    end

    it "400s when the data envelope is missing" do
      post "/api/v1/search_synonym_groups", params: {}, headers: service_headers, as: :json

      expect(response).to have_http_status(:bad_request)
    end

    it "requires authentication" do
      post "/api/v1/search_synonym_groups", params: payload, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "PATCH /api/v1/search_synonym_groups/:id" do
    it "updates a group as the service" do
      group = create(:search_synonym_group)

      patch "/api/v1/search_synonym_groups/#{group.group_id}",
        params: { data: { created_by: "5678" } }, headers: service_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "created_by")).to eq("5678")
      expect(group.reload.created_by).to eq("5678")
    end

    it "forbids a regular user" do
      group = create(:search_synonym_group)

      patch "/api/v1/search_synonym_groups/#{group.group_id}",
        params: { data: { created_by: "hijacked" } }, headers: auth_headers_for(create(:user)), as: :json

      expect(response).to have_http_status(:forbidden)
      expect(group.reload.created_by).not_to eq("hijacked")
    end

    it "404s for an unknown id" do
      patch "/api/v1/search_synonym_groups/999999999",
        params: { data: { created_by: "x" } }, headers: service_headers, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "DELETE /api/v1/search_synonym_groups/:id" do
    it "deletes the group and cascades to its terms" do
      group = create(:search_synonym_group)
      synonym = create(:search_synonym, group: group)

      delete "/api/v1/search_synonym_groups/#{group.group_id}", headers: service_headers

      expect(response).to have_http_status(:ok)
      expect(json).to eq("deleted" => true)
      expect(GamedbSearchSynonymGroup.exists?(group.group_id)).to be(false)
      expect(GamedbSearchSynonym.exists?(synonym.term_id)).to be(false)
    end

    it "forbids a regular user" do
      group = create(:search_synonym_group)

      delete "/api/v1/search_synonym_groups/#{group.group_id}", headers: auth_headers_for(create(:user))

      expect(response).to have_http_status(:forbidden)
      expect(GamedbSearchSynonymGroup.exists?(group.group_id)).to be(true)
    end

    it "404s for an unknown id" do
      delete "/api/v1/search_synonym_groups/999999999", headers: auth_headers_for(create(:user, :admin))

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "DELETE /api/v1/search_synonym_groups/:id/terms" do
    it "bulk-deletes the group's terms but keeps the group" do
      group = create(:search_synonym_group)
      create_list(:search_synonym, 2, group: group)
      untouched = create(:search_synonym)

      delete "/api/v1/search_synonym_groups/#{group.group_id}/terms",
        headers: auth_headers_for(create(:user, :admin))

      expect(response).to have_http_status(:ok)
      expect(json).to eq("deleted" => true, "count" => 2)
      expect(GamedbSearchSynonymGroup.exists?(group.group_id)).to be(true)
      expect(group.synonyms.count).to eq(0)
      expect(GamedbSearchSynonym.exists?(untouched.term_id)).to be(true)
    end

    it "forbids a regular user" do
      group = create(:search_synonym_group)
      create(:search_synonym, group: group)

      delete "/api/v1/search_synonym_groups/#{group.group_id}/terms", headers: auth_headers_for(create(:user))

      expect(response).to have_http_status(:forbidden)
      expect(group.synonyms.count).to eq(1)
    end

    it "404s for an unknown group" do
      delete "/api/v1/search_synonym_groups/999999999/terms", headers: service_headers

      expect(response).to have_http_status(:not_found)
    end
  end

  # Every role the site can sign in as, plus the bot (#333). Reads are open to
  # any signed-in caller; the replace-terms write is Admin and up.
  roles = {
    "a plain member" => [ {}, {} ],
    "a Regulars role holder" => [ { role_regular: true }, {} ],
    "a Moderator" => [ { role_moderator: true }, {} ],
    "an Admin" => [ { role_admin: true }, {} ],
    "a Superadmin" => [ {}, { is_dev: true } ]
  }
  writers = [ "an Admin", "a Superadmin" ]

  describe "GET /api/v1/search_synonym_groups?include=terms as every role" do
    it "refuses an anonymous caller" do
      get "/api/v1/search_synonym_groups", params: { include: "terms" }

      expect(response).to have_http_status(:unauthorized)
    end

    roles.each do |label, (flags, token_flags)|
      it "lets #{label} read groups with their terms" do
        create(:search_synonym, term_text: "Roles Read zq1")

        get "/api/v1/search_synonym_groups", params: { q: "roles read zq1", include: "terms" },
          headers: auth_headers_for(create(:user, **flags), **token_flags)

        expect(response).to have_http_status(:ok)
        expect(json.dig("data", 0, "terms", 0, "term_text")).to eq("Roles Read zq1")
      end
    end

    it "lets the service read groups with their terms" do
      create(:search_synonym, term_text: "Roles Read zq2")

      get "/api/v1/search_synonym_groups", params: { q: "roles read zq2", include: "terms" }, headers: service_headers

      expect(json.dig("data", 0, "terms", 0, "term_text")).to eq("Roles Read zq2")
    end
  end

  describe "PUT /api/v1/search_synonym_groups/:id/terms" do
    let(:group) { create(:search_synonym_group) }
    let!(:old_term) { create(:search_synonym, group: group, term_text: "Old Term") }
    let(:payload) { { data: { terms: [ "FF7", "Final Fantasy VII" ] } } }
    let(:admin) { create(:user, role_admin: true) }

    def replace(group_id, body, headers)
      put "/api/v1/search_synonym_groups/#{group_id}/terms", params: body, headers: headers, as: :json
    end

    def stored_terms(group)
      GamedbSearchSynonym.where(group_id: group.group_id).order(:term_text).pluck(:term_text, :term_norm)
    end

    it "swaps all of the group's terms and returns the group with its new terms" do
      untouched = create(:search_synonym, term_text: "Elsewhere")

      replace(group.group_id, payload, auth_headers_for(admin))

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "group_id")).to eq(group.group_id)
      expect(json.dig("data", "terms").map { |t| [ t["term_text"], t["term_norm"], t["created_by"] ] }).to eq([
        [ "FF7", "ff7", admin.user_id ],
        [ "Final Fantasy VII", "finalfantasyvii", admin.user_id ]
      ])
      expect(stored_terms(group)).to eq([ %w[FF7 ff7], [ "Final Fantasy VII", "finalfantasyvii" ] ])
      expect(GamedbSearchSynonym.exists?(untouched.term_id)).to be(true)
    end

    it "keeps a term whose text is unchanged, re-saved as part of the new set" do
      replace(group.group_id, { data: { terms: [ "Old Term", "New Term" ] } }, auth_headers_for(admin))

      expect(response).to have_http_status(:ok)
      expect(stored_terms(group).map(&:first)).to eq([ "New Term", "Old Term" ])
    end

    it "trims terms, drops blanks and keeps the first of terms that normalise alike" do
      replace(group.group_id, { data: { terms: [ "  FF7 ", "", "ff-7", "Final Fantasy VII" ] } }, service_headers)

      expect(response).to have_http_status(:ok)
      expect(stored_terms(group).map(&:first)).to eq([ "FF7", "Final Fantasy VII" ])
    end

    it "records the signed-in Admin as creator, never a created_by from the body" do
      replace(group.group_id, { data: { terms: %w[aa bb], created_by: "spoofed" } }, auth_headers_for(admin))

      expect(GamedbSearchSynonym.where(group_id: group.group_id).pluck(:created_by).uniq).to eq([ admin.user_id ])
    end

    it "takes the bot's created_by from the body" do
      replace(group.group_id, { data: { terms: %w[aa bb], created_by: "4242" } }, service_headers)

      expect(GamedbSearchSynonym.where(group_id: group.group_id).pluck(:created_by).uniq).to eq([ "4242" ])
    end

    it "422s with fewer than two distinct terms and keeps the old terms" do
      replace(group.group_id, { data: { terms: [ "FF7", "ff 7", " " ] } }, auth_headers_for(admin))

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json.fetch("error")).to eq("A synonym group needs at least two different terms.")
      expect(stored_terms(group)).to eq([ [ "Old Term", "oldterm" ] ])
    end

    it "422s on a term with no letters or numbers and keeps the old terms" do
      replace(group.group_id, { data: { terms: [ "FF7", "!!!" ] } }, auth_headers_for(admin))

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json.fetch("error")).to eq("Synonym terms must include letters or numbers.")
      expect(stored_terms(group)).to eq([ [ "Old Term", "oldterm" ] ])
    end

    it "422s when terms is not a list of strings" do
      replace(group.group_id, { data: { terms: "FF7" } }, auth_headers_for(admin))

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json.fetch("error")).to eq("terms must be a list of strings.")
    end

    it "rolls back every change when one term cannot be saved" do
      replace(group.group_id, { data: { terms: [ "FF7", "x" * 300 ] } }, auth_headers_for(admin))

      expect(response).to have_http_status(:unprocessable_entity)
      expect(stored_terms(group)).to eq([ [ "Old Term", "oldterm" ] ])
    end

    it "400s when the data envelope is missing" do
      replace(group.group_id, {}, auth_headers_for(admin))

      expect(response).to have_http_status(:bad_request)
    end

    it "404s for an unknown group" do
      replace(999_999_999, payload, auth_headers_for(admin))

      expect(response).to have_http_status(:not_found)
    end

    it "refuses an anonymous caller" do
      replace(group.group_id, payload, {})

      expect(response).to have_http_status(:unauthorized)
      expect(stored_terms(group)).to eq([ [ "Old Term", "oldterm" ] ])
    end

    it "lets the service replace terms" do
      replace(group.group_id, payload, service_headers)

      expect(response).to have_http_status(:ok)
    end

    roles.each do |label, (flags, token_flags)|
      allowed = writers.include?(label)

      it "#{allowed ? 'lets' : 'refuses'} #{label}" do
        replace(group.group_id, payload, auth_headers_for(create(:user, **flags), **token_flags))

        if allowed
          expect(response).to have_http_status(:ok)
          expect(stored_terms(group).map(&:first)).to eq([ "FF7", "Final Fantasy VII" ])
        else
          expect(response).to have_http_status(:forbidden)
          expect(json).to eq("error" => "forbidden")
          expect(stored_terms(group)).to eq([ [ "Old Term", "oldterm" ] ])
        end
      end
    end
  end
end
