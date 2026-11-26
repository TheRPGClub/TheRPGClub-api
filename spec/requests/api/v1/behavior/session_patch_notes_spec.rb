# frozen_string_literal: true

require "rails_helper"

# The session's Patch Notes unseen flag (spec api#510, ticket api#512): the
# sidebar shows "NEW" while a published Patch is newer than the member's
# Patch Mark, without another request. False for anyone not shown Patch
# Notes: a member who hid it, a member while it is in Preview, the service
# token. `patch_mark` comes along so the website can mark unseen Patches.
RSpec.describe "session patch_notes_unseen", type: :request do
  let(:member) { create(:user, role_member: true) }

  def publish_patch
    Patch.create!(status: Patch::PUBLISHED, published_at: Time.current).reload
  end

  def session_for(headers)
    get "/api/v1/session", headers: headers
    expect(response).to have_http_status(:ok)
    json.slice("patch_notes_unseen", "patch_mark")
  end

  def set_mark(user, number) = PatchMark.advance!(user.user_id, number)

  it "is false while there is no published Patch" do
    Patch.create!

    expect(session_for(auth_headers_for(member))).to eq("patch_notes_unseen" => false, "patch_mark" => nil)
  end

  it "is true on a first visit once a Patch is published" do
    publish_patch

    expect(session_for(auth_headers_for(member))).to eq("patch_notes_unseen" => true, "patch_mark" => nil)
  end

  it "is false once the member has seen the newest Patch" do
    patch = publish_patch
    set_mark(member, patch.number)

    expect(session_for(auth_headers_for(member))).to eq("patch_notes_unseen" => false, "patch_mark" => patch.number)
  end

  it "is true again when a newer Patch is published" do
    first = publish_patch
    set_mark(member, first.number)
    publish_patch

    expect(session_for(auth_headers_for(member))).to eq("patch_notes_unseen" => true, "patch_mark" => first.number)
  end

  it "is false, with no mark, for a member who hides Patch Notes" do
    first = publish_patch
    set_mark(member, first.number)
    publish_patch
    MemberFeaturePreference.create!(user_id: member.user_id, feature_key: "patch_notes")

    expect(session_for(auth_headers_for(member))).to eq("patch_notes_unseen" => false, "patch_mark" => nil)
  end

  it "is false for a member while Patch Notes is in Preview, and true for staff" do
    set_feature_flag("patch_notes", "preview")
    publish_patch
    admin = create(:user, role_member: true, role_admin: true)

    expect(session_for(auth_headers_for(member))["patch_notes_unseen"]).to be(false)
    expect(session_for(auth_headers_for(admin))["patch_notes_unseen"]).to be(true)
  end

  it "is false for everyone when Patch Notes is Off" do
    set_feature_flag("patch_notes", "off")
    publish_patch

    expect(session_for(auth_headers_for(member))["patch_notes_unseen"]).to be(false)
  end

  it "is false for the service token" do
    publish_patch

    expect(session_for(service_headers)).to eq("patch_notes_unseen" => false, "patch_mark" => nil)
  end
end
