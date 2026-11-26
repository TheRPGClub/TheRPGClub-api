# frozen_string_literal: true

require "rails_helper"

# Pinned Pages (spec api#416, ticket api#418; docs/adr/0012): the pages a
# member put at the top of their own sidebar. A member with no saved list
# follows the club default. Reads return only the pages the member can see
# now; a save keeps the hidden ones. Only the member themself may read or
# change their list.
RSpec.describe "api/v1/pinned_pages behavior", type: :request do
  let(:member) { create(:user, role_member: true) }

  def path_for(user) = "/api/v1/users/#{user.user_id}/pinned_pages"

  def pinned_for(user, headers = auth_headers_for(user))
    get path_for(user), headers: headers
    expect(response).to have_http_status(:ok)
    json.fetch("data")
  end

  def pin(user, pages, headers = auth_headers_for(user))
    put path_for(user), params: { data: { pages: pages } }, headers: headers, as: :json
  end

  describe "GET /api/v1/users/:user_id/pinned_pages" do
    it "gives a member with no saved list the club default" do
      expect(pinned_for(member)).to eq(
        "user_id" => member.user_id,
        "pages" => %w[voting games members news],
        "customised" => false
      )
    end

    it "says the list is customised after any save, even one keeping the default" do
      pin(member, %w[voting games members news])

      expect(json.dig("data", "customised")).to be(true)
      expect(pinned_for(member)["customised"]).to be(true)
    end
  end

  describe "PUT /api/v1/users/:user_id/pinned_pages" do
    it "saves the member's list in their order and reads it back" do
      pin(member, %w[news releases members])

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "pages")).to eq(%w[news releases members])
      expect(pinned_for(member)["pages"]).to eq(%w[news releases members])
    end

    it "saves an empty list, so the member no longer follows the default" do
      pin(member, [])

      expect(response).to have_http_status(:ok)
      expect(pinned_for(member)["pages"]).to eq([])
    end

    it "refuses an unknown page, changing nothing" do
      pin(member, %w[news dashboard])

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["error"]).to eq("unknown page: dashboard")
      expect(pinned_for(member)["pages"]).to eq(%w[voting games members news])
    end

    it "refuses a page pinned twice" do
      pin(member, %w[news members news])

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["error"]).to eq("news is pinned twice")
    end

    it "refuses a seventh pin" do
      pin(member, %w[voting gotm_history challenges games releases achievements journals])

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["error"]).to eq("at most 6 Pinned Pages, counting 0 you can't see right now")
      expect(pinned_for(member)["pages"]).to eq(%w[voting games members news])
    end

    it "refuses a body without a list of pages" do
      put path_for(member), params: { data: { pages: "news" } }, headers: auth_headers_for(member), as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["error"]).to eq("pages must be a list of page keys")
    end
  end

  describe "DELETE /api/v1/users/:user_id/pinned_pages" do
    def reset(user, headers = auth_headers_for(user))
      delete path_for(user), headers: headers
    end

    it "resets the member to the club default, no longer customised" do
      pin(member, %w[news releases])

      reset(member)

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to eq(
        "user_id" => member.user_id,
        "pages" => %w[voting games members news],
        "customised" => false
      )
      expect(pinned_for(member)).to include("pages" => %w[voting games members news], "customised" => false)
    end

    it "lets later changes to the club default reach the member" do
      pin(member, [])
      reset(member)

      stub_const("PinnedPages::DEFAULT", %w[releases members].freeze)

      expect(pinned_for(member)["pages"]).to eq(%w[releases members])
    end

    it "makes the list customised again on the next save" do
      pin(member, %w[news])
      reset(member)

      pin(member, %w[members])

      expect(pinned_for(member)).to include("pages" => %w[members], "customised" => true)
    end

    it "is fine for a member who already follows the default" do
      reset(member)

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "customised")).to be(false)
    end

    it "refuses another member's list, changing nothing" do
      other = create(:user, role_member: true)
      pin(other, %w[news])

      reset(other, auth_headers_for(member))

      expect(response).to have_http_status(:forbidden)
      expect(pinned_for(other)).to include("pages" => %w[news], "customised" => true)
    end

    it "refuses the bot's service token" do
      reset(member, service_headers)

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "who may read and change a list" do
    it "refuses another member's list" do
      other = create(:user, role_member: true)

      get path_for(other), headers: auth_headers_for(member)
      expect(response).to have_http_status(:forbidden)

      pin(other, %w[news], auth_headers_for(member))
      expect(response).to have_http_status(:forbidden)
      expect(pinned_for(other)["pages"]).to eq(%w[voting games members news])
    end

    it "refuses staff reading another member's list" do
      get path_for(member), headers: auth_headers_for(create(:user, :admin), is_dev: true)

      expect(response).to have_http_status(:forbidden)
    end

    it "refuses the bot's service token" do
      get path_for(member), headers: service_headers

      expect(response).to have_http_status(:forbidden)
    end

    it "requires a session" do
      get path_for(member)

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "staff pages" do
    let(:staff_pages) { %w[staff_desk voting_console synonyms live_events public_reminders feedback_review] }

    def staff_pinned_for(user, **token)
      headers = auth_headers_for(user, **token)
      pin(user, staff_pages, headers)
      expect(response).to have_http_status(:ok)
      pinned_for(user, headers)["pages"]
    end

    it "shows a member none of them, while keeping them" do
      expect(staff_pinned_for(member)).to eq([])
    end

    it "shows a Moderator the Moderator pages" do
      moderator = create(:user, role_moderator: true)

      expect(staff_pinned_for(moderator)).to eq(%w[staff_desk live_events])
    end

    it "shows an Admin the Moderator and Admin pages" do
      expect(staff_pinned_for(create(:user, :admin))).to eq(
        %w[staff_desk voting_console synonyms live_events public_reminders]
      )
    end

    it "shows a Superadmin every staff page" do
      expect(staff_pinned_for(create(:user), is_dev: true)).to eq(staff_pages)
    end
  end

  describe "pins the member can't see right now" do
    it "leaves out a page whose Feature is Off, and brings it back when it is Live again" do
      pin(member, %w[news releases members])
      set_feature_flag("release_calendar", "off")

      expect(pinned_for(member)["pages"]).to eq(%w[news members])

      set_feature_flag("release_calendar", "live")
      expect(pinned_for(member)["pages"]).to eq(%w[news releases members])
    end

    it "lets a member pin the Review Feed, behind the Reviews Feature" do
      pin(member, %w[reviews members])
      expect(response).to have_http_status(:ok)
      expect(pinned_for(member)["pages"]).to eq(%w[reviews members])

      set_feature_flag("reviews", "off")
      expect(pinned_for(member)["pages"]).to eq(%w[members])
    end

    it "lets a member pin the Franchises index, which needs no Feature" do
      pin(member, %w[franchises members])
      expect(response).to have_http_status(:ok)
      expect(pinned_for(member)["pages"]).to eq(%w[franchises members])
    end

    it "lets a member pin the GOTY Vote, behind its Feature" do
      set_feature_flag("goty_vote", "live")
      pin(member, %w[goty members])
      expect(response).to have_http_status(:ok)
      expect(pinned_for(member)["pages"]).to eq(%w[goty members])

      set_feature_flag("goty_vote", "off")
      expect(pinned_for(member)["pages"]).to eq(%w[members])
    end

    it "lets a member pin the Roadmap, behind its Feature and their Feature Preference" do
      pin(member, %w[roadmap members])
      expect(response).to have_http_status(:ok)
      expect(pinned_for(member)["pages"]).to eq(%w[roadmap members])

      MemberFeaturePreference.create!(user_id: member.user_id, feature_key: "roadmap")
      expect(pinned_for(member)["pages"]).to eq(%w[members])

      MemberFeaturePreference.where(user_id: member.user_id).delete_all
      set_feature_flag("roadmap", "preview")
      expect(pinned_for(member)["pages"]).to eq(%w[members])
    end

    it "leaves out a default page the member hid with a Feature Preference" do
      MemberFeaturePreference.create!(user_id: member.user_id, feature_key: "news_hub")

      expect(pinned_for(member)["pages"]).to eq(%w[voting games members])
    end

    it "keeps hidden pins through a save of the visible list, after it and in their order" do
      pin(member, %w[news releases members journals games])
      set_feature_flag("release_calendar", "off")
      MemberFeaturePreference.create!(user_id: member.user_id, feature_key: "journals")

      pin(member, %w[games members])
      expect(json.dig("data", "pages")).to eq(%w[games members])

      set_feature_flag("release_calendar", "live")
      MemberFeaturePreference.delete_all
      expect(pinned_for(member)["pages"]).to eq(%w[games members releases journals])
    end

    it "keeps a hidden default page through the member's first save" do
      set_feature_flag("news_hub", "off")

      pin(member, %w[members games])

      set_feature_flag("news_hub", "live")
      expect(pinned_for(member)["pages"]).to eq(%w[members games news])
    end

    it "counts hidden pins toward the limit" do
      pin(member, %w[voting games members news releases journals])
      set_feature_flag("release_calendar", "off")

      pin(member, %w[voting games members news journals codex])

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["error"]).to eq("at most 6 Pinned Pages, counting 1 you can't see right now")
    end

    it "accepts a page the member can't see, and keeps it" do
      set_feature_flag("journals", "off")

      pin(member, %w[journals members])

      expect(response).to have_http_status(:ok)
      set_feature_flag("journals", "live")
      expect(pinned_for(member)["pages"]).to eq(%w[journals members])
    end
  end

  describe "a saved page the API no longer knows" do
    it "is ignored on read and dropped on the next save" do
      pin(member, %w[news members])
      MemberPinnedPage.create!(user_id: member.user_id, page_key: "retired_page", position: 1)
      MemberPinnedPage.where(user_id: member.user_id, page_key: "members").update_all(position: 2)

      expect(pinned_for(member)["pages"]).to eq(%w[news members])

      pin(member, %w[members news])
      expect(MemberPinnedPage.where(user_id: member.user_id).order(:position).pluck(:page_key)).to eq(%w[members news])
    end
  end

  describe "the session payload" do
    def session_pins(user, headers = auth_headers_for(user))
      get "/api/v1/session", headers: headers
      expect(response).to have_http_status(:ok)
      json.fetch("pinned_pages")
    end

    it "carries the club default for a member who never saved a list" do
      expect(session_pins(member)).to eq(%w[voting games members news])
    end

    it "carries the member's visible Pinned Pages in their order" do
      pin(member, %w[codex releases members])
      set_feature_flag("club_codex", "off")

      expect(session_pins(member)).to eq(%w[releases members])
    end

    it "is empty for the bot's service token" do
      expect(session_pins(nil, service_headers)).to eq([])
    end

    it "says whether the member customised their list" do
      get "/api/v1/session", headers: auth_headers_for(member)
      expect(json["pinned_pages_customised"]).to be(false)

      pin(member, %w[news])
      get "/api/v1/session", headers: auth_headers_for(member)
      expect(json["pinned_pages_customised"]).to be(true)

      delete path_for(member), headers: auth_headers_for(member)
      get "/api/v1/session", headers: auth_headers_for(member)
      expect(json["pinned_pages_customised"]).to be(false)
    end

    it "carries the club's default and limit" do
      get "/api/v1/session", headers: auth_headers_for(member)

      expect(json).to include("pinned_pages_default" => %w[voting games members news], "pinned_pages_limit" => 6)
    end

    it "gives the room for visible pins, less the pins the member can't see right now" do
      get "/api/v1/session", headers: auth_headers_for(member)
      expect(json["pinned_pages_room"]).to eq(6)

      pin(member, %w[voting games releases journals])
      set_feature_flag("release_calendar", "off")
      MemberFeaturePreference.create!(user_id: member.user_id, feature_key: "journals")

      get "/api/v1/session", headers: auth_headers_for(member)
      expect(json).to include("pinned_pages" => %w[voting games], "pinned_pages_room" => 4)
    end

    it "gives the bot's service token the whole limit as room" do
      get "/api/v1/session", headers: service_headers

      expect(json).to include("pinned_pages_room" => 6, "pinned_pages_limit" => 6)
    end

    it "is not customised for the bot's service token" do
      get "/api/v1/session", headers: service_headers

      expect(json["pinned_pages_customised"]).to be(false)
    end
  end
end
