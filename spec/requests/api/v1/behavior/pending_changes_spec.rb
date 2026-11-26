# frozen_string_literal: true

require "rails_helper"

# Pending Changes (GLOSSARY.md "Pending Change"; spec api#510, ticket api#514).
# The versioning job reports each merged pull request with its own narrow
# release token; the versions read shows each repo's current version; Admins
# and Superadmins list Pending Changes, dismiss them and set which ones a Patch
# covers.
RSpec.describe "api/v1/pending_changes behavior", type: :request do
  let(:admin) { create(:user, role_member: true, role_admin: true) }
  let(:moderator) { create(:user, role_member: true, role_moderator: true) }
  let(:member) { create(:user, role_member: true) }

  def change(**data)
    { repo: "www", pr_number: 240, type: "feat", title: "feat(www): Patch Notes pages", version: "1.1.0" }.merge(data)
  end

  def intake(headers: release_headers, **data)
    post "/api/v1/pending_changes", params: { data: change(**data) }, headers: headers, as: :json
  end

  describe "intake" do
    it "records a merged pull request with the release token" do
      intake(patch_note: "Patch Notes now has its own page.")

      expect(response).to have_http_status(:created)
      expect(json.fetch("data")).to include(
        "repo" => "www", "pr_number" => 240, "type" => "feat", "title" => "feat(www): Patch Notes pages",
        "version" => "1.1.0", "patch_note" => "Patch Notes now has its own page.", "section" => "new",
        "status" => "open", "patch_number" => nil, "dismissed_at" => nil
      )
    end

    it "leaves the Patch note line optional" do
      intake

      expect(response).to have_http_status(:created)
      expect(json.dig("data", "patch_note")).to be_nil
    end

    it "refuses the bot's token, a member's session and no token" do
      intake(headers: service_headers)
      expect(response).to have_http_status(:forbidden)

      intake(headers: auth_headers_for(admin, is_dev: true))
      expect(response).to have_http_status(:forbidden)

      intake(headers: {})
      expect(response).to have_http_status(:unauthorized)

      intake(headers: { "Authorization" => "Bearer not-the-release-token" })
      expect(response).to have_http_status(:unauthorized)

      expect(staff_list).to be_empty
    end

    it "never signs anything else in with the release token" do
      post "/api/v1/patches", params: { data: { body: "x", cut_body: "x" } }, headers: release_headers, as: :json
      expect(response).to have_http_status(:unauthorized)

      get "/api/v1/session", headers: release_headers
      expect(response).to have_http_status(:unauthorized)

      get "/api/v1/pending_changes", headers: release_headers
      expect(response).to have_http_status(:unauthorized)
    end

    it "changes nothing when the same pull request is reported again" do
      intake(patch_note: "First words.")
      first = json.fetch("data")

      intake(title: "feat(www): renamed", version: "9.9.9", patch_note: "Other words.")

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to eq(first)
      expect(staff_list.size).to eq(1)
      expect(versions.fetch("www")).to eq("1.1.0")
    end

    it "keeps the same pull request number apart in different repos" do
      intake(repo: "www")
      intake(repo: "bot", version: "4.2.1")

      expect(response).to have_http_status(:created)
      expect(staff_list.size).to eq(2)
    end

    it "refuses an unknown repo or type, a version that isn't x.y.z and missing fields" do
      [ { repo: "site" }, { type: "style" }, { version: "1.2" }, { version: "v1.2.3" }, { pr_number: 0 },
        { pr_number: "abc" }, { title: "" }, { title: nil }, { patch_note: 5 } ].each do |data|
        intake(**data)
        expect(response).to have_http_status(:unprocessable_content), "#{data} got #{response.status}"
        expect(json.fetch("error")).to eq("invalid_pending_change")
      end
    end

    it "sorts types into New, Improved and Fixed" do
      { "feat" => "new", "perf" => "improved", "fix" => "fixed", "refactor" => "improved" }.each_with_index do |(type, section), i|
        intake(pr_number: 300 + i, type: type)
        expect(json.dig("data", "section")).to eq(section), type
      end
    end

    it "still collects while Patch Notes is Off" do
      set_feature_flag("patch_notes", "off")
      intake

      expect(response).to have_http_status(:created)
      set_feature_flag("patch_notes", "preview")
      expect(staff_list.size).to eq(1)
    end
  end

  def versions
    get "/api/v1/versions"
    expect(response).to have_http_status(:ok)
    json.fetch("data")
  end

  describe "versions" do
    it "is null for each repo until versioning starts" do
      expect(versions).to eq("api" => nil, "bot" => nil, "www" => nil)
    end

    it "shows each repo's version from its newest intake, to anyone, even while Off" do
      intake(repo: "api", pr_number: 1, version: "1.0.1")
      intake(repo: "api", pr_number: 2, version: "1.1.0")
      intake(repo: "bot", pr_number: 2, version: "4.3.0")
      set_feature_flag("patch_notes", "off")

      expect(versions).to eq("api" => "1.1.0", "bot" => "4.3.0", "www" => nil)
    end
  end

  def staff_list(status: "all", headers: auth_headers_for(admin))
    get "/api/v1/pending_changes", params: { status: status }, headers: headers
    expect(response).to have_http_status(:ok)
    json.fetch("data")
  end

  # Records a Pending Change and returns its id.
  def pending(**data)
    intake(**data)
    json.dig("data", "id")
  end

  def staff(action, id, as: admin, is_dev: false)
    post "/api/v1/pending_changes/#{id}/#{action}", headers: auth_headers_for(as, is_dev: is_dev)
  end

  def new_patch
    post "/api/v1/patches", params: { data: { body: "", cut_body: "" } }, headers: auth_headers_for(admin), as: :json
    json.dig("data", "number")
  end

  def cover(number, ids, as: admin)
    put "/api/v1/patches/#{number}/pending_changes", params: { data: { ids: ids } },
      headers: auth_headers_for(as), as: :json
  end

  describe "the staff list" do
    it "lists newest first and filters by open, covered and dismissed" do
      open_id = pending(pr_number: 1)
      dismissed_id = pending(pr_number: 2)
      covered_id = pending(pr_number: 3)
      staff(:dismiss, dismissed_id)
      cover(new_patch, [ covered_id ])

      expect(staff_list.pluck("id")).to eq([ covered_id, dismissed_id, open_id ])
      expect(staff_list(status: "open").pluck("id")).to eq([ open_id ])
      expect(staff_list(status: "covered").pluck("id")).to eq([ covered_id ])
      expect(staff_list(status: "dismissed").pluck("id")).to eq([ dismissed_id ])
    end

    it "defaults to open and refuses an unknown status" do
      open_id = pending(pr_number: 1)
      staff(:dismiss, pending(pr_number: 2))

      get "/api/v1/pending_changes", headers: auth_headers_for(admin)
      expect(json.fetch("data").pluck("id")).to eq([ open_id ])

      get "/api/v1/pending_changes", params: { status: "merged" }, headers: auth_headers_for(admin)
      expect(response).to have_http_status(:bad_request)
      expect(json.fetch("error")).to eq("invalid_status")
    end

    it "is for Admins and Superadmins signed in on the website" do
      pending
      expect(staff_list(headers: auth_headers_for(member, is_dev: true)).size).to eq(1)

      [ auth_headers_for(moderator), auth_headers_for(member), service_headers ].each do |headers|
        get "/api/v1/pending_changes", headers: headers
        expect(response).to have_http_status(:forbidden)
      end

      get "/api/v1/pending_changes"
      expect(response).to have_http_status(:unauthorized)
    end

    it "follows the Feature gate: staff in Preview, nobody when Off" do
      pending
      set_feature_flag("patch_notes", "off")

      get "/api/v1/pending_changes", headers: auth_headers_for(admin)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "dismissing" do
    it "dismisses an open Pending Change and undoes it" do
      id = pending

      staff(:dismiss, id)
      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("id" => id, "status" => "dismissed")
      expect(json.dig("data", "dismissed_at")).to be_present

      staff(:undismiss, id)
      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("id" => id, "status" => "open", "dismissed_at" => nil)
    end

    it "refuses dismissing twice, undoing an open one and dismissing a covered one" do
      id = pending
      staff(:undismiss, id)
      expect([ response.status, json.fetch("error") ]).to eq([ 422, "not_dismissed" ])

      staff(:dismiss, id)
      staff(:dismiss, id)
      expect([ response.status, json.fetch("error") ]).to eq([ 422, "already_dismissed" ])

      other = pending(pr_number: 2)
      cover(new_patch, [ other ])
      staff(:dismiss, other)
      expect([ response.status, json.fetch("error") ]).to eq([ 422, "covered" ])
    end

    it "is for Admins and Superadmins only" do
      id = pending

      [ moderator, member ].each do |user|
        staff(:dismiss, id, as: user)
        expect(response).to have_http_status(:forbidden)
      end
      post "/api/v1/pending_changes/#{id}/dismiss", headers: service_headers
      expect(response).to have_http_status(:forbidden)
      post "/api/v1/pending_changes/#{id}/dismiss", headers: release_headers
      expect(response).to have_http_status(:unauthorized)

      staff(:dismiss, id, as: member, is_dev: true)
      expect(response).to have_http_status(:ok)
    end

    it "is not found for an unknown id" do
      staff(:dismiss, 0)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "covering" do
    it "sets which Pending Changes a Patch covers, and uncovers the ones left out" do
      a = pending(pr_number: 1)
      b = pending(pr_number: 2)
      c = pending(pr_number: 3)
      number = new_patch

      cover(number, [ a, b ])
      expect(response).to have_http_status(:ok)
      expect(json.fetch("data").pluck("id")).to contain_exactly(a, b)
      expect(json.fetch("data").pluck("patch_number")).to eq([ number, number ])
      expect(json.fetch("data").pluck("status")).to eq(%w[covered covered])

      cover(number, [ b, c ])
      expect(json.fetch("data").pluck("id")).to contain_exactly(b, c)
      expect(staff_list(status: "open").pluck("id")).to eq([ a ])

      cover(number, [])
      expect(json.fetch("data")).to be_empty
      expect(staff_list(status: "open").size).to eq(3)
    end

    it "refuses a dismissed one, one another Patch covers, and unknown ids, changing nothing" do
      a = pending(pr_number: 1)
      b = pending(pr_number: 2)
      c = pending(pr_number: 3)
      staff(:dismiss, b)
      other = new_patch
      cover(other, [ c ])
      number = new_patch

      [ [ [ a, b ], "dismissed" ], [ [ a, c ], "covered_elsewhere" ], [ [ a, 0 ], "not_found" ],
        [ "x", "invalid_pending_changes" ] ].each do |ids, error|
        cover(number, ids)
        expect([ response.status, json.fetch("error") ]).to eq([ error == "not_found" ? 404 : 422, error ]), ids.to_s
      end
      expect(staff_list(status: "open").pluck("id")).to eq([ a ])
    end

    it "lists what a Patch covers" do
      a = pending(pr_number: 1)
      pending(pr_number: 2)
      number = new_patch
      cover(number, [ a ])

      get "/api/v1/pending_changes", params: { status: "covered", patch: number }, headers: auth_headers_for(admin)
      expect(json.fetch("data").pluck("id")).to eq([ a ])
      get "/api/v1/pending_changes", params: { status: "covered", patch: new_patch }, headers: auth_headers_for(admin)
      expect(json.fetch("data")).to be_empty
    end

    it "uncovers its Pending Changes when a draft Patch is deleted" do
      a = pending
      number = new_patch
      cover(number, [ a ])

      delete "/api/v1/patches/#{number}", headers: auth_headers_for(admin)
      expect(response).to have_http_status(:ok)
      expect(staff_list(status: "open").pluck("id")).to eq([ a ])
    end

    it "is for Admins and Superadmins only, and not found for an unknown Patch" do
      a = pending
      number = new_patch

      [ moderator, member ].each do |user|
        cover(number, [ a ], as: user)
        expect(response).to have_http_status(:forbidden)
      end
      put "/api/v1/patches/#{number}/pending_changes", params: { data: { ids: [ a ] } }, headers: service_headers, as: :json
      expect(response).to have_http_status(:forbidden)

      cover(number + 100, [ a ])
      expect(response).to have_http_status(:not_found)
    end
  end
end
