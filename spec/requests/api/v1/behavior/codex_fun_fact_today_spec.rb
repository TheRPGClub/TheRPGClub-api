# frozen_string_literal: true

require "rails_helper"

# Today's Daily Fun Fact (spec #397; review of #411): GET
# /api/v1/codex/fun_facts/today reads the Fun Fact the Daily Fun Fact posted
# for the club date (America/New_York). Before today's post (15:00 New
# York) it is the latest earlier one, so the Codex page never goes blank in
# the morning. A pure read: it draws nothing and posts nothing.
RSpec.describe "api/v1/codex/fun_facts/today behavior", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:regular) { create(:user, role_member: true, role_regular: true) }
  let(:member) { create(:user, role_member: true) }
  let(:admin) { create(:user, role_member: true, role_admin: true) }
  let(:zone) { ActiveSupport::TimeZone["America/New_York"] }

  # As ClubCodex::DailyFunFactJob leaves it: drawn (so shown) at 15:00 New
  # York on the club date, and recorded as that day's post.
  def post_daily_fun_fact(club_date, body: "Posted on #{club_date}.")
    fun_fact = create(:codex_entry, :fun_fact, author: regular, body: body,
      last_shown_at: zone.local(club_date.year, club_date.month, club_date.day, 15))
    DailyFunFactPost.create!(club_date: club_date, entry_id: fun_fact.id)
    fun_fact
  end

  def today(headers = auth_headers_for(member), params = {})
    get "/api/v1/codex/fun_facts/today", params: params, headers: headers
    json
  end

  it "answers with today's Daily Fun Fact and its club date" do
    travel_to(zone.local(2026, 11, 18, 16)) do
      post_daily_fun_fact(Date.new(2026, 11, 17))
      fun_fact = post_daily_fun_fact(Date.new(2026, 11, 18), body: "Rhea named the bot.")

      expect(today).to include("club_date" => "2026-11-18")
      expect(response).to have_http_status(:ok)
      expect(json.fetch("fun_fact")).to include(
        "id" => fun_fact.id, "part" => "fun_fact", "body" => "Rhea named the bot.",
        "author" => include("user_id" => regular.user_id), "viewer" => { "can_edit" => false, "can_delete" => false }
      )
    end
  end

  it "answers with the latest earlier one before today's is posted" do
    travel_to(zone.local(2026, 11, 18, 9)) do
      post_daily_fun_fact(Date.new(2026, 11, 14))
      fun_fact = post_daily_fun_fact(Date.new(2026, 11, 16))

      expect(today).to include("club_date" => "2026-11-16")
      expect(json.dig("fun_fact", "id")).to eq(fun_fact.id)
    end
  end

  it "goes by the club date in New York, not UTC" do
    # 02:00 UTC on the 19th is still the 18th in New York.
    travel_to(Time.utc(2026, 11, 19, 2)) do
      post_daily_fun_fact(Date.new(2026, 11, 18))
      post_daily_fun_fact(Date.new(2026, 11, 19))

      expect(today.fetch("club_date")).to eq("2026-11-18")
    end
  end

  it "answers null when nothing has been posted yet" do
    create(:codex_entry, :fun_fact, author: regular)

    expect(today).to eq("fun_fact" => nil, "club_date" => nil)
    expect(response).to have_http_status(:ok)
  end

  it "answers null when the posted Fun Fact has since been deleted" do
    travel_to(zone.local(2026, 11, 18, 16)) do
      post_daily_fun_fact(Date.new(2026, 11, 17))
      deleted = post_daily_fun_fact(Date.new(2026, 11, 18))

      delete "/api/v1/codex/fun_facts/#{deleted.id}", headers: auth_headers_for(regular)
      expect(response).to have_http_status(:ok)

      expect(today).to eq("fun_fact" => nil, "club_date" => nil)
    end
  end

  it "draws nothing, so the Fun Fact queue doesn't move" do
    travel_to(zone.local(2026, 11, 18, 16)) do
      posted = post_daily_fun_fact(Date.new(2026, 11, 18))
      waiting = create(:codex_entry, :fun_fact, author: regular, body: "Next in the queue.")

      2.times { today }

      expect(posted.reload.last_shown_at).to eq(zone.local(2026, 11, 18, 15))
      expect(waiting.reload.last_shown_at).to be_nil
      expect(DailyFunFactPost.count).to eq(1)
      post "/api/v1/codex/fun_facts/draw", headers: auth_headers_for(member), as: :json
      expect(json.dig("fun_fact", "body")).to eq("Next in the queue.")
    end
  end

  it "shows the viewer flags of the member reading it" do
    travel_to(zone.local(2026, 11, 18, 16)) do
      post_daily_fun_fact(Date.new(2026, 11, 18))

      expect(today(auth_headers_for(regular)).dig("fun_fact", "viewer"))
        .to eq("can_edit" => true, "can_delete" => true)
    end
  end

  it "answers the bot, for the member it names or for none" do
    travel_to(zone.local(2026, 11, 18, 16)) do
      post_daily_fun_fact(Date.new(2026, 11, 18))

      expect(today(service_headers).dig("fun_fact", "viewer")).to eq("can_edit" => false, "can_delete" => false)
      expect(response).to have_http_status(:ok)

      expect(today(service_headers, acting_user_id: regular.user_id).dig("fun_fact", "viewer"))
        .to eq("can_edit" => true, "can_delete" => true)
    end
  end

  it "refuses a signed-out visitor" do
    get "/api/v1/codex/fun_facts/today"

    expect(response).to have_http_status(:unauthorized)
  end

  describe "the feature gate" do
    def today_status(headers)
      get "/api/v1/codex/fun_facts/today", headers: headers
      response.status
    end

    it "hides it from non-staff in Preview, and answers staff and the bot" do
      set_feature_flag("club_codex", "preview")

      expect(today_status(auth_headers_for(member))).to eq(404)
      expect(today_status(auth_headers_for(admin))).to eq(200)
      expect(today_status(service_headers)).to eq(200)
    end

    it "hides it from everyone but the bot when Off" do
      set_feature_flag("club_codex", "off")

      expect(today_status(auth_headers_for(admin))).to eq(404)
      expect(today_status(auth_headers_for(member, is_dev: true))).to eq(404)
      expect(today_status(service_headers)).to eq(200)
    end
  end
end
