# frozen_string_literal: true

require "rails_helper"

# The session's `features` list (spec #347, ticket #348): for the signed-in
# viewer, each Feature they may see, its Feature Flag state, whether it is
# hideable, whether it is shown, and whether it is shown only because the
# viewer is staff. Admins and Superadmins see Preview; Moderators and members
# do not; nobody sees Off. Starts with no stored Feature Flags, so every
# Feature reads Preview until an example sets one.
RSpec.describe "session features", type: :request, feature_flags: :none do
  def features_for(headers)
    get "/api/v1/session", headers: headers
    expect(response).to have_http_status(:ok)
    json.fetch("features")
  end

  def entry(features, key)
    features.find { |feature| feature["key"] == key }
  end

  describe "for a member" do
    let(:member) { create(:user, role_member: true) }

    it "lists a Live Feature as shown" do
      set_feature_flag("reviews", "live")

      expect(entry(features_for(auth_headers_for(member)), "reviews")).to eq(
        "key" => "reviews", "name" => "Reviews", "state" => "live",
        "hideable" => true, "shown" => true, "preview" => false
      )
    end

    it "lists all 11 Features in registry order when every Feature is Live, Core ones not hideable" do
      set_all_feature_flags("live")

      features = features_for(auth_headers_for(member))

      expect(features.map { |f| [ f["key"], f["name"], f["hideable"] ] }).to eq([
        [ "game_index", "Game Index", false ],
        [ "voting_gotm", "Voting & GOTM", false ],
        [ "backlog", "Backlog", false ],
        [ "collection", "Collection", false ],
        [ "now_playing", "Now Playing", false ],
        [ "game_completions", "Game Completions", false ],
        [ "reviews", "Reviews", true ],
        [ "achievement_hub", "Achievement Hub", true ],
        [ "giveaways", "Giveaways", true ],
        [ "journals", "Journals", true ],
        [ "suggestions", "Suggestions", true ]
      ])
      expect(features).to all(include("state" => "live", "shown" => true, "preview" => false))
    end

    it "never receives a Preview or Off Feature" do
      set_all_feature_flags("live")
      set_feature_flag("journals", "preview")
      set_feature_flag("giveaways", "off")

      keys = features_for(auth_headers_for(member)).map { |f| f["key"] }

      expect(keys).not_to include("journals", "giveaways")
      expect(keys.size).to eq(9)
    end

    it "reads a Feature with no stored state as Preview, so it is not listed" do
      expect(features_for(auth_headers_for(member))).to eq([])
    end
  end

  describe "for a Moderator" do
    it "sees only Live Features, like a member" do
      moderator = create(:user, role_moderator: true)
      set_feature_flag("reviews", "live")
      set_feature_flag("journals", "preview")
      set_feature_flag("giveaways", "off")

      expect(features_for(auth_headers_for(moderator)).map { |f| f["key"] }).to eq([ "reviews" ])
    end
  end

  shared_examples "a staff session" do
    before do
      set_feature_flag("reviews", "live")
      set_feature_flag("journals", "preview")
      set_feature_flag("giveaways", "off")
    end

    it "shows a Live Feature without the preview mark" do
      expect(entry(features_for(headers), "reviews")).to include(
        "state" => "live", "shown" => true, "preview" => false
      )
    end

    it "shows a Preview Feature, marked as shown only because the viewer is staff" do
      expect(entry(features_for(headers), "journals")).to eq(
        "key" => "journals", "name" => "Journals", "state" => "preview",
        "hideable" => true, "shown" => true, "preview" => true
      )
    end

    it "lists an Off Feature with its state but does not show it" do
      expect(entry(features_for(headers), "giveaways")).to include(
        "state" => "off", "shown" => false, "preview" => false
      )
    end

    it "lists every Feature, reading one with no stored state as Preview" do
      features = features_for(headers)

      expect(features.size).to eq(11)
      expect(entry(features, "game_index")).to include("state" => "preview", "shown" => true, "preview" => true)
    end
  end

  describe "for an Admin" do
    let(:headers) { auth_headers_for(create(:user, :admin)) }

    it_behaves_like "a staff session"
  end

  describe "for a Superadmin" do
    let(:headers) { auth_headers_for(create(:user), is_dev: true) }

    it_behaves_like "a staff session"
  end

  describe "for the bot's service token" do
    let(:headers) { service_headers }

    it_behaves_like "a staff session"
  end

  it "follows a flag change on the next request" do
    member_headers = auth_headers_for(create(:user))
    set_feature_flag("suggestions", "live")
    expect(features_for(member_headers).map { |f| f["key"] }).to eq([ "suggestions" ])

    set_feature_flag("suggestions", "off")

    expect(features_for(member_headers)).to eq([])
  end

  # Feature Preferences and the staff show-Preview setting (ticket #352)
  # narrow `shown` only: the Feature stays listed with its state.
  def hide(user, *keys, headers: auth_headers_for(user))
    patch "/api/v1/users/#{user.user_id}/feature_preferences",
      params: { data: { hidden: keys.index_with(true) } }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
  end

  def set_show_preview(user, value, headers: auth_headers_for(user))
    patch "/api/v1/users/#{user.user_id}/feature_preferences",
      params: { data: { show_preview_features: value } }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
  end

  describe "with Feature Preferences" do
    before { set_all_feature_flags("live") }

    it "lists a Feature the member hid as not shown" do
      member = create(:user, role_member: true)
      hide(member, "reviews")

      features = features_for(auth_headers_for(member))

      expect(entry(features, "reviews")).to include("state" => "live", "hideable" => true, "shown" => false)
      expect(entry(features, "journals")).to include("shown" => true)
    end

    it "hides a Feature for a Moderator who hid it" do
      moderator = create(:user, role_moderator: true)
      hide(moderator, "giveaways")

      expect(entry(features_for(auth_headers_for(moderator)), "giveaways")).to include("shown" => false)
    end

    it "keeps the preference through any flag change" do
      member = create(:user)
      hide(member, "journals")

      set_feature_flag("journals", "off")
      expect(entry(features_for(auth_headers_for(member)), "journals")).to be_nil
      set_feature_flag("journals", "live")

      expect(entry(features_for(auth_headers_for(member)), "journals")).to include("state" => "live", "shown" => false)
    end

    it "hides a Preview Feature an Admin hid while testing others" do
      admin = create(:user, :admin)
      set_feature_flag("journals", "preview")
      set_feature_flag("giveaways", "preview")
      hide(admin, "journals")

      features = features_for(auth_headers_for(admin))

      expect(entry(features, "journals")).to include("state" => "preview", "shown" => false, "preview" => true)
      expect(entry(features, "giveaways")).to include("state" => "preview", "shown" => true, "preview" => true)
    end

    it "only affects the member who hid it" do
      hider = create(:user)
      hide(hider, "reviews")

      expect(entry(features_for(auth_headers_for(create(:user))), "reviews")).to include("shown" => true)
    end
  end

  describe "with the staff show-Preview setting off" do
    before do
      set_feature_flag("reviews", "live")
      set_feature_flag("journals", "preview")
      set_feature_flag("giveaways", "off")
    end

    shared_examples "a staff member seeing Features as a member would" do
      before { set_show_preview(staff_user, false, headers: headers) }

      it "does not show a Preview Feature, still listing it with its state" do
        expect(entry(features_for(headers), "journals")).to include(
          "state" => "preview", "shown" => false, "preview" => true
        )
      end

      it "shows exactly the Features a member is shown" do
        shown = features_for(headers).select { |f| f["shown"] }.map { |f| f["key"] }
        member_shown = features_for(auth_headers_for(create(:user))).select { |f| f["shown"] }.map { |f| f["key"] }

        expect(shown).to eq(member_shown)
        expect(shown).to eq([ "reviews" ])
      end

      it "shows Preview Features again once the setting is back on" do
        set_show_preview(staff_user, true, headers: headers)

        expect(entry(features_for(headers), "journals")).to include("shown" => true)
      end
    end

    describe "for an Admin" do
      let(:staff_user) { create(:user, :admin) }
      let(:headers) { auth_headers_for(staff_user) }

      it_behaves_like "a staff member seeing Features as a member would"
    end

    describe "for a Superadmin" do
      let(:staff_user) { create(:user) }
      let(:headers) { auth_headers_for(staff_user, is_dev: true) }

      it_behaves_like "a staff member seeing Features as a member would"
    end
  end
end
