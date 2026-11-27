# frozen_string_literal: true

require "rails_helper"

# The Member's Theme (spec api#523, ticket api#524; docs/adr/0017). The
# session reports the Theme a Member sees right now, already resolved, and
# the Themes they may choose with their stored choice. PUT /api/v1/me/theme
# stores it. The Themes Feature decides who may choose a Theme other than
# the default; an unreleased Theme is staff-only even while Themes is Live.
RSpec.describe "api/v1/me/theme behavior", type: :request do
  let(:member) { create(:user, role_member: true) }
  let(:admin) { create(:user, role_member: true, role_admin: true) }
  let(:viewers) { { "staff" => admin, "member" => member } }

  def monthly_issue(available: true)
    { "key" => "monthly-issue", "name" => "Monthly Issue", "released" => true, "available" => available }
  end

  def aero(available:, released: false)
    { "key" => "aero", "name" => "Frutiger Aero", "released" => released, "available" => available }
  end

  def session_theme(user, headers = auth_headers_for(user))
    get "/api/v1/session", headers: headers
    expect(response).to have_http_status(:ok)
    json.slice("theme", "themes")
  end

  def choose(user, theme, headers = auth_headers_for(user))
    put "/api/v1/me/theme", params: { theme: theme }, headers: headers, as: :json
  end

  def store(user, theme) = user.update_columns(theme: theme)

  def stored(user) = user.reload.theme

  # Aero as a Released Theme, as the owner's cutover (api#525) will mark it.
  def release_aero
    list = Themes::LIST.map { |theme| theme.key == "aero" ? theme.with(released: true) : theme }.freeze
    stub_const("Themes::LIST", list)
    stub_const("Themes::BY_KEY", list.index_by(&:key).freeze)
  end

  # Who may choose Aero, by the Themes Feature's state, the viewer, and
  # whether Aero is released.
  {
    [ "off", "staff", false ] => false,
    [ "off", "staff", true ] => false,
    [ "off", "member", false ] => false,
    [ "off", "member", true ] => false,
    [ "preview", "staff", false ] => true,
    [ "preview", "staff", true ] => true,
    [ "preview", "member", false ] => false,
    [ "preview", "member", true ] => false,
    [ "live", "staff", false ] => true,
    [ "live", "staff", true ] => true,
    [ "live", "member", false ] => false,
    [ "live", "member", true ] => true
  }.each do |(state, viewer, released), allowed|
    describe "Themes #{state}, #{viewer}, Aero #{released ? 'released' : 'unreleased'}" do
      let(:user) { viewers.fetch(viewer) }

      before do
        set_feature_flag("themes", state)
        release_aero if released
      end

      if allowed
        it "lets them choose Aero, and the session shows it" do
          choose(user, "aero")

          expected = {
            "theme" => "aero",
            "themes" => { "chosen" => "aero", "list" => [ monthly_issue, aero(available: true, released: released) ] }
          }
          expect(response).to have_http_status(:ok)
          expect(json).to eq(expected)
          expect(stored(user)).to eq("aero")
          expect(session_theme(user)).to eq(expected)
        end

        it "offers Aero in the picker before they choose it" do
          expect(session_theme(user)).to eq(
            "theme" => "monthly-issue",
            "themes" => { "chosen" => nil, "list" => [ monthly_issue, aero(available: true, released: released) ] }
          )
        end
      else
        it "refuses Aero with 403, changing nothing" do
          choose(user, "aero")

          expect(response).to have_http_status(:forbidden)
          expect(stored(user)).to be_nil
        end

        it "offers only the default, and reports the default over a stored Aero" do
          expect(session_theme(user)).to eq(
            "theme" => "monthly-issue", "themes" => { "chosen" => nil, "list" => [ monthly_issue ] }
          )

          store(user, "aero")

          expect(session_theme(user)).to eq(
            "theme" => "monthly-issue",
            "themes" => { "chosen" => "aero", "list" => [ monthly_issue, aero(available: false, released: released) ] }
          )
        end
      end

      it "always lets them choose the default" do
        choose(user, "monthly-issue")

        expect(response).to have_http_status(:ok)
        expect(json["theme"]).to eq("monthly-issue")
        expect(json.dig("themes", "chosen")).to eq("monthly-issue")
        expect(stored(user)).to eq("monthly-issue")
      end
    end
  end

  it "reports the default for a stored key the API no longer knows, keeping it" do
    set_feature_flag("themes", "live")
    store(admin, "vaporwave")

    expect(session_theme(admin)).to eq(
      "theme" => "monthly-issue",
      "themes" => { "chosen" => "vaporwave", "list" => [ monthly_issue, aero(available: true) ] }
    )
    expect(stored(admin)).to eq("vaporwave")
  end

  it "keeps a stored Theme while it is unavailable and brings it back when it is available again" do
    set_feature_flag("themes", "preview")
    choose(admin, "aero")
    expect(response).to have_http_status(:ok)

    set_feature_flag("themes", "off")
    expect(session_theme(admin)["theme"]).to eq("monthly-issue")
    expect(stored(admin)).to eq("aero")

    set_feature_flag("themes", "live")
    expect(session_theme(admin)["theme"]).to eq("aero")
  end

  it "keeps a member's Aero through a Preview and brings it back once Aero is released and Live" do
    set_feature_flag("themes", "live")
    release_aero
    choose(member, "aero")
    expect(response).to have_http_status(:ok)

    set_feature_flag("themes", "preview")
    expect(session_theme(member)["theme"]).to eq("monthly-issue")
    expect(stored(member)).to eq("aero")

    set_feature_flag("themes", "live")
    expect(session_theme(member)["theme"]).to eq("aero")
  end

  it "resets to the club default with null" do
    set_feature_flag("themes", "live")
    store(admin, "aero")

    choose(admin, nil)

    expect(response).to have_http_status(:ok)
    expect(json).to eq(
      "theme" => "monthly-issue",
      "themes" => { "chosen" => nil, "list" => [ monthly_issue, aero(available: true) ] }
    )
    expect(stored(admin)).to be_nil
  end

  it "lets a member reset with null even while Themes is Off" do
    set_feature_flag("themes", "off")
    store(member, "aero")

    choose(member, nil)

    expect(response).to have_http_status(:ok)
    expect(stored(member)).to be_nil
  end

  it "refuses an unknown key with 422, changing nothing" do
    set_feature_flag("themes", "live")
    store(admin, "aero")

    choose(admin, "vaporwave")

    expect(response).to have_http_status(:unprocessable_content)
    expect(json["error"]).to eq("unknown Theme: vaporwave")
    expect(stored(admin)).to eq("aero")
  end

  it "refuses a non-string Theme with 422" do
    choose(admin, 5)

    expect(response).to have_http_status(:unprocessable_content)
  end

  it "answers 400 without a theme parameter" do
    put "/api/v1/me/theme", params: {}, headers: auth_headers_for(member), as: :json

    expect(response).to have_http_status(:bad_request)
  end

  it "refuses the bot's service token" do
    choose(member, nil, service_headers)

    expect(response).to have_http_status(:forbidden)
  end

  it "requires a signed-in caller" do
    put "/api/v1/me/theme", params: { theme: nil }, as: :json

    expect(response).to have_http_status(:unauthorized)
  end

  it "gives the service token's session only the default" do
    set_feature_flag("themes", "live")

    get "/api/v1/session", headers: service_headers

    expect(json.slice("theme", "themes")).to eq(
      "theme" => "monthly-issue", "themes" => { "chosen" => nil, "list" => [ monthly_issue ] }
    )
  end
end
