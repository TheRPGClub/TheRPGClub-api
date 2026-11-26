# frozen_string_literal: true

require "rails_helper"

# The Patch Mark (spec api#510, ticket api#512): the number of the newest
# Patch a member has seen. The website reads it to mark unseen Patches "NEW"
# and moves it forward when the member opens /patch-notes or a Patch page. It
# never moves backwards.
RSpec.describe "api/v1/patch_mark behavior", type: :request do
  let(:member) { create(:user, role_member: true) }

  def publish_patch
    Patch.create!(status: Patch::PUBLISHED, published_at: Time.current).reload
  end

  def path_for(user) = "/api/v1/users/#{user.user_id}/patch_mark"

  def mark_for(user)
    get path_for(user), headers: auth_headers_for(user)
    expect(response).to have_http_status(:ok)
    json.fetch("data")
  end

  def put_mark(user, data, headers = auth_headers_for(user))
    put path_for(user), params: { data: data }, headers: headers, as: :json
  end

  describe "GET /api/v1/users/:user_id/patch_mark" do
    it "has no Patch Mark until one is set" do
      expect(mark_for(member)).to eq("user_id" => member.user_id, "patch_mark" => nil, "unseen" => false)
    end

    it "calls every published Patch unseen while there is no Patch Mark" do
      publish_patch

      expect(mark_for(member)).to include("patch_mark" => nil, "unseen" => true)
    end

    it "reads back the Patch Mark once set, seen up to the newest Patch" do
      patch = publish_patch
      put_mark(member, { patch_mark: patch.number })

      expect(mark_for(member)).to eq("user_id" => member.user_id, "patch_mark" => patch.number, "unseen" => false)
    end

    it "calls a Patch published after the Patch Mark unseen" do
      first = publish_patch
      put_mark(member, { patch_mark: first.number })
      publish_patch

      expect(mark_for(member)).to include("patch_mark" => first.number, "unseen" => true)
    end

    it "ignores drafts newer than the Patch Mark" do
      first = publish_patch
      put_mark(member, { patch_mark: first.number })
      Patch.create!

      expect(mark_for(member)["unseen"]).to be(false)
    end

    it "forbids another member" do
      get path_for(member), headers: auth_headers_for(create(:user, role_member: true))

      expect(response).to have_http_status(:forbidden)
    end

    it "forbids the bot's service token, since the Patch Mark only shapes the website" do
      get path_for(member), headers: service_headers

      expect(response).to have_http_status(:forbidden)
    end

    it "is not found when the Patch Notes Feature is Off" do
      set_feature_flag("patch_notes", "off")
      get path_for(member), headers: auth_headers_for(member)

      expect(response).to have_http_status(:not_found)
    end

    it "requires authentication" do
      get path_for(member)

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "PUT /api/v1/users/:user_id/patch_mark" do
    let!(:first) { publish_patch }
    let!(:second) { publish_patch }

    it "sets a first Patch Mark" do
      put_mark(member, { patch_mark: first.number })

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to eq("user_id" => member.user_id, "patch_mark" => first.number, "unseen" => true)
    end

    it "moves the Patch Mark forward" do
      put_mark(member, { patch_mark: first.number })
      put_mark(member, { patch_mark: second.number })

      expect(json.fetch("data")).to include("patch_mark" => second.number, "unseen" => false)
      expect(mark_for(member)["patch_mark"]).to eq(second.number)
    end

    it "never moves the Patch Mark backwards: it keeps the stored one and answers with it" do
      put_mark(member, { patch_mark: second.number })
      put_mark(member, { patch_mark: first.number })

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "patch_mark")).to eq(second.number)
      expect(mark_for(member)["patch_mark"]).to eq(second.number)
    end

    it "clamps a number past the newest published Patch to it, so a later Patch still reads unseen" do
      draft = Patch.create!.reload
      put_mark(member, { patch_mark: draft.number + 5 })

      expect(json.fetch("data")).to include("patch_mark" => second.number, "unseen" => false)

      draft.publish!
      expect(mark_for(member)).to include("patch_mark" => second.number, "unseen" => true)
    end

    [ 0, -1, "3", 2.5, nil ].each do |value|
      it "refuses patch_mark #{value.inspect} with 422 and keeps the Patch Mark" do
        put_mark(member, { patch_mark: first.number })
        put_mark(member, { patch_mark: value })

        expect(response).to have_http_status(:unprocessable_content)
        expect(json["error"]).to eq("patch_mark must be a positive whole number")
        expect(mark_for(member)["patch_mark"]).to eq(first.number)
      end
    end

    it "forbids another member and leaves the Patch Mark unset" do
      put_mark(member, { patch_mark: first.number }, auth_headers_for(create(:user, role_member: true)))

      expect(response).to have_http_status(:forbidden)
      expect(mark_for(member)["patch_mark"]).to be_nil
    end

    it "forbids the bot's service token" do
      put_mark(member, { patch_mark: first.number }, service_headers)

      expect(response).to have_http_status(:forbidden)
      expect(mark_for(member)["patch_mark"]).to be_nil
    end

    it "refuses a request without data with 400" do
      put path_for(member), params: {}, headers: auth_headers_for(member), as: :json

      expect(response).to have_http_status(:bad_request)
    end

    it "is not found when the Patch Notes Feature is Off" do
      set_feature_flag("patch_notes", "off")
      put_mark(member, { patch_mark: first.number })

      expect(response).to have_http_status(:not_found)
    end
  end
end
