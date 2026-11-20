# frozen_string_literal: true

require "rails_helper"

# Dashboard Panels (spec api#421, ticket api#422; docs/adr/0012): the blocks of
# club or personal activity a member shows below the current issue on their
# own dashboard, in their order. A member with no saved list follows the club
# default. Reads return only the panels the member can see now; a save keeps
# the hidden ones. Only the member themself may read or change their list.
RSpec.describe "api/v1/dashboard_panels behavior", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:member) { create(:user, role_member: true) }
  let(:default) { %w[news now_playing_club releases achievements_club challenges_club] }

  def path_for(user) = "/api/v1/users/#{user.user_id}/dashboard_panels"

  def panels_for(user, headers = auth_headers_for(user))
    get path_for(user), headers: headers
    expect(response).to have_http_status(:ok)
    json.fetch("data")
  end

  def show(user, panels, headers = auth_headers_for(user))
    put path_for(user), params: { data: { panels: panels } }, headers: headers, as: :json
  end

  describe "GET /api/v1/users/:user_id/dashboard_panels" do
    it "gives a member with no saved list the club default, not customised" do
      expect(panels_for(member)).to include(
        "user_id" => member.user_id,
        "panels" => default,
        "customised" => false
      )
    end

    it "says the list is customised after any save, even one keeping the default" do
      show(member, default)

      expect(json.dig("data", "customised")).to be(true)
      expect(panels_for(member)["customised"]).to be(true)
    end
  end

  describe "PUT /api/v1/users/:user_id/dashboard_panels" do
    it "saves the member's list in their order and reads it back" do
      show(member, %w[birthdays reviews news])

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "panels")).to eq(%w[birthdays reviews news])
      expect(panels_for(member)).to include("panels" => %w[birthdays reviews news], "customised" => true)
    end

    it "takes any number of panels" do
      everything = DashboardPanels.keys.reverse

      show(member, everything)

      expect(response).to have_http_status(:ok)
      expect(panels_for(member)["panels"]).to eq(everything)
    end

    it "saves an empty list, so the member no longer follows the default" do
      show(member, [])

      expect(response).to have_http_status(:ok)
      expect(panels_for(member)).to include("panels" => [], "customised" => true)
    end

    it "refuses an unknown panel, changing nothing" do
      show(member, %w[news collection])

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["error"]).to eq("unknown panel: collection")
      expect(panels_for(member)).to include("panels" => default, "customised" => false)
    end

    it "refuses a panel shown twice, changing nothing" do
      show(member, %w[news reviews news])

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["error"]).to eq("news is shown twice")
      expect(panels_for(member)["panels"]).to eq(default)
    end

    it "refuses a body without a list of panels" do
      put path_for(member), params: { data: { panels: "news" } }, headers: auth_headers_for(member), as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["error"]).to eq("panels must be a list of panel keys")
    end
  end

  describe "DELETE /api/v1/users/:user_id/dashboard_panels" do
    def reset(user, headers = auth_headers_for(user))
      delete path_for(user), headers: headers
    end

    it "resets the member to the club default, no longer customised" do
      show(member, %w[reviews])

      reset(member)

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("panels" => default, "customised" => false)
      expect(panels_for(member)).to include("panels" => default, "customised" => false)
    end

    it "lets later changes to the club default reach the member" do
      show(member, [])
      reset(member)

      stub_const("DashboardPanels::DEFAULT", %w[birthdays news].freeze)

      expect(panels_for(member)["panels"]).to eq(%w[birthdays news])
    end

    it "is fine for a member who already follows the default" do
      reset(member)

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "customised")).to be(false)
    end

    it "refuses another member's list, changing nothing" do
      other = create(:user, role_member: true)
      show(other, %w[reviews])

      reset(other, auth_headers_for(member))

      expect(response).to have_http_status(:forbidden)
      expect(panels_for(other)).to include("panels" => %w[reviews], "customised" => true)
    end
  end

  describe "who may read and change a list" do
    it "refuses another member's list" do
      other = create(:user, role_member: true)

      get path_for(other), headers: auth_headers_for(member)
      expect(response).to have_http_status(:forbidden)

      show(other, %w[reviews], auth_headers_for(member))
      expect(response).to have_http_status(:forbidden)

      post "#{path_for(other)}/seen", headers: auth_headers_for(member)
      expect(response).to have_http_status(:forbidden)

      expect(panels_for(other)).to include("panels" => default, "customised" => false)
    end

    it "refuses staff reading another member's list" do
      get path_for(member), headers: auth_headers_for(create(:user, :admin), is_dev: true)

      expect(response).to have_http_status(:forbidden)
    end

    it "refuses the bot's service token" do
      get path_for(member), headers: service_headers
      expect(response).to have_http_status(:forbidden)

      show(member, %w[news], service_headers)
      expect(response).to have_http_status(:forbidden)

      delete path_for(member), headers: service_headers
      expect(response).to have_http_status(:forbidden)

      post "#{path_for(member)}/seen", headers: service_headers
      expect(response).to have_http_status(:forbidden)
    end

    it "requires a session" do
      get path_for(member)

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "panels the member can't see right now" do
    it "leaves out a panel whose Feature is Off, and brings it back when it is Live again" do
      show(member, %w[news releases birthdays])
      set_feature_flag("release_calendar", "off")

      expect(panels_for(member)["panels"]).to eq(%w[news birthdays])

      set_feature_flag("release_calendar", "live")
      expect(panels_for(member)["panels"]).to eq(%w[news releases birthdays])
    end

    it "leaves out a default panel the member hid with a Feature Preference" do
      MemberFeaturePreference.create!(user_id: member.user_id, feature_key: "news_hub")

      expect(panels_for(member)["panels"]).to eq(%w[now_playing_club releases achievements_club challenges_club])
    end

    it "keeps hidden panels through a save of the visible list, after it and in their order" do
      show(member, %w[news releases birthdays journals reviews])
      set_feature_flag("release_calendar", "off")
      MemberFeaturePreference.create!(user_id: member.user_id, feature_key: "journals")

      show(member, %w[reviews birthdays])
      expect(json.dig("data", "panels")).to eq(%w[reviews birthdays])

      set_feature_flag("release_calendar", "live")
      MemberFeaturePreference.delete_all
      expect(panels_for(member)["panels"]).to eq(%w[reviews birthdays releases journals])
    end

    it "keeps a hidden default panel through the member's first save" do
      set_feature_flag("news_hub", "off")

      show(member, %w[birthdays releases])

      set_feature_flag("news_hub", "live")
      expect(panels_for(member)["panels"]).to eq(%w[birthdays releases news])
    end

    it "accepts a panel the member can't see, and keeps it" do
      set_feature_flag("journals", "off")

      show(member, %w[journals birthdays])

      expect(response).to have_http_status(:ok)
      set_feature_flag("journals", "live")
      expect(panels_for(member)["panels"]).to eq(%w[journals birthdays])
    end

    it "leaves the panel out of the catalogue too" do
      set_feature_flag("now_playing", "off")

      keys = panels_for(member)["catalogue"].pluck("key")

      expect(keys).not_to include("now_playing_club", "now_playing_mine")
      expect(keys).to include("birthdays", "news")
    end
  end

  describe "a saved panel the API no longer knows" do
    it "is ignored on read and dropped on the next save" do
      show(member, %w[news birthdays])
      MemberDashboardPanel.create!(user_id: member.user_id, panel_key: "retired_panel", position: 1)
      MemberDashboardPanel.where(user_id: member.user_id, panel_key: "birthdays").update_all(position: 2)

      expect(panels_for(member)["panels"]).to eq(%w[news birthdays])

      show(member, %w[birthdays news])
      expect(MemberDashboardPanel.where(user_id: member.user_id).order(:position).pluck(:panel_key))
        .to eq(%w[birthdays news])
    end
  end

  describe "the catalogue" do
    it "lists every panel the member can see, shown or not, with its scope, in the club's order" do
      catalogue = panels_for(member)["catalogue"]

      expect(catalogue.pluck("key")).to eq(%w[
        news now_playing_club releases achievements_club challenges_club now_playing_mine achievements_mine
        challenge_runs_mine completions_club completions_mine backlog_pick reviews journals giveaways
        suggestions codex birthdays
      ])
      expect(catalogue.first).to eq("key" => "news", "scope" => "club", "new" => false)
      expect(catalogue.find { |panel| panel["key"] == "backlog_pick" }["scope"]).to eq("mine")
    end
  end

  describe "new panels" do
    def seen(user, headers = auth_headers_for(user))
      post "#{path_for(user)}/seen", headers: headers
    end

    def new_keys(user) = panels_for(user)["catalogue"].select { |panel| panel["new"] }.pluck("key")

    # Birthdays added after launch, the rest at launch.
    before do
      later = DashboardPanels.all.map do |panel|
        panel.key == "birthdays" ? panel.with(added_on: Date.new(2026, 12, 10)) : panel
      end
      stub_const("DashboardPanels::BY_KEY", later.index_by(&:key).freeze)
    end

    it "shows nothing as new to a member who never opened edit mode" do
      travel_to(Time.utc(2026, 12, 20)) do
        expect(new_keys(member)).to eq([])
      end
    end

    it "marks panels added after the member last opened edit mode as new" do
      travel_to(Time.utc(2026, 12, 1)) { seen(member) }

      travel_to(Time.utc(2026, 12, 20)) do
        expect(new_keys(member)).to eq(%w[birthdays])
      end
    end

    it "clears them once the member opens edit mode again" do
      travel_to(Time.utc(2026, 12, 1)) { seen(member) }

      travel_to(Time.utc(2026, 12, 20)) do
        seen(member)

        expect(response).to have_http_status(:ok)
        expect(json.dig("data", "catalogue").select { |panel| panel["new"] }).to eq([])
        expect(new_keys(member)).to eq([])
      end
    end
  end
end
