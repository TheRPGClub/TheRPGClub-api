# frozen_string_literal: true

require "rails_helper"

# Staff flag control (spec #347, ticket #351): Admins and Superadmins list
# every Feature with its Feature Flag and change it. When the bot calls, it
# names the acting Discord user and the same Admin/Superadmin rule applies to
# that user, never to the service token (ADR 0005).
RSpec::Matchers.define_negated_matcher :not_change, :change

RSpec.describe "staff flag control", type: :request do
  let(:admin) { create(:user, role_admin: true, global_name: "Ada") }

  def entry(key)
    json.fetch("data").find { |feature| feature["key"] == key }
  end

  describe "GET /api/v1/features" do
    it "lists every Feature in registry order with its state, Core/hideable, coverage and last change" do
      set_feature_flag("journals", "off", by: admin.user_id, reason: "Journal sync broken, pausing")

      get "/api/v1/features", headers: auth_headers_for(admin)

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data").map { |f| [ f["key"], f["state"] ] }).to eq([
        [ "game_index", "live" ], [ "voting_gotm", "live" ], [ "backlog", "live" ], [ "collection", "live" ],
        [ "now_playing", "live" ], [ "game_completions", "live" ], [ "reviews", "live" ],
        [ "achievement_hub", "live" ], [ "giveaways", "live" ], [ "journals", "off" ], [ "suggestions", "live" ],
        [ "news_hub", "live" ]
      ])
      expect(entry("journals")).to include(
        "name" => "Journals", "core" => false, "hideable" => true,
        "coverage" => { "website" => [ "Game Journals", "Game page Journals", "Profile Game Journal" ], "bot" => [ "/game-journal" ], "posts" => [] }
      )
      expect(entry("journals").fetch("last_change")).to include(
        "from_state" => "live", "to_state" => "off", "changed_by" => admin.user_id,
        "changed_by_name" => "Ada", "reason" => "Journal sync broken, pausing"
      )
      expect(entry("journals").dig("last_change", "changed_at")).to be_present
      expect(entry("game_index")).to include("core" => true, "hideable" => false)
      expect(entry("game_index").fetch("last_change")).to include(
        "from_state" => "preview", "to_state" => "live", "changed_by" => "system", "changed_by_name" => nil
      )
    end

    it "reads a Feature with no stored state as Preview, with no last change", feature_flags: :none do
      get "/api/v1/features", headers: auth_headers_for(admin)

      expect(entry("reviews")).to include("state" => "preview", "last_change" => nil)
    end

    it "is for Admins and Superadmins; Moderators and members get 403" do
      moderator = create(:user, role_moderator: true)
      member = create(:user, role_member: true)

      get "/api/v1/features", headers: auth_headers_for(member, is_dev: true)
      expect(response).to have_http_status(:ok)

      [ moderator, member ].each do |user|
        get "/api/v1/features", headers: auth_headers_for(user)
        expect(response).to have_http_status(:forbidden)
        expect(json).to eq("error" => "forbidden")
      end
    end

    it "needs a sign-in" do
      get "/api/v1/features"

      expect(response).to have_http_status(:unauthorized)
    end

    describe "from the bot" do
      it "answers when the acting Discord user is an Admin or has the dev role" do
        superadmin = create(:user, role_dev: true)

        [ admin, superadmin ].each do |user|
          get "/api/v1/features", params: { acting_user_id: user.user_id }, headers: service_headers
          expect(response).to have_http_status(:ok)
          expect(json.fetch("data").size).to eq(12)
        end
      end

      it "is forbidden when the acting Discord user is not staff, or has no member record" do
        moderator = create(:user, role_moderator: true)

        [ moderator.user_id, "999999999999999999" ].each do |user_id|
          get "/api/v1/features", params: { acting_user_id: user_id }, headers: service_headers
          expect(response).to have_http_status(:forbidden)
        end
      end

      it "is a bad request without the acting Discord user" do
        get "/api/v1/features", headers: service_headers

        expect(response).to have_http_status(:bad_request)
        expect(json).to eq("error" => "acting_user_id required")
      end
    end
  end

  describe "PATCH /api/v1/features/:key" do
    def set_flag(key, data, headers: auth_headers_for(admin))
      patch "/api/v1/features/#{key}", params: { data: data }, headers: headers, as: :json
    end

    it "sets the state, logs who, from, to and why, and answers with the Feature's entry" do
      set_flag("journals", { state: "off", reason: "Journal sync broken, pausing" })

      expect(response).to have_http_status(:ok)
      expect(json.fetch("meta")).to eq("changed" => true)
      expect(json.fetch("data")).to include("key" => "journals", "state" => "off")
      expect(json.dig("data", "last_change")).to include(
        "from_state" => "live", "to_state" => "off", "changed_by" => admin.user_id, "changed_by_name" => "Ada",
        "reason" => "Journal sync broken, pausing"
      )

      get "/api/v1/features", headers: auth_headers_for(admin)
      expect(entry("journals")).to include("state" => "off")
      expect(entry("journals").dig("last_change", "reason")).to eq("Journal sync broken, pausing")
    end

    it "enqueues the admin-channel announcement, without a Feature key for the bot to route it by" do
      expect { set_flag("reviews", { state: "preview", reason: "Testing the new tab" }) }
        .to change(BotJob, :count).by(1)

      job = BotJob.last
      expect(job.kind).to eq("feature_flag_changed")
      expect(job.requested_by_user_id).to eq(admin.user_id)
      expect(job.summary).to eq("Feature Flag Reviews: live to preview")
      expect(job.payload).to eq(
        "key" => "reviews", "name" => "Reviews", "from_state" => "live", "to_state" => "preview",
        "changed_by" => admin.user_id, "changed_by_name" => "Ada", "reason" => "Testing the new tab"
      )
    end

    it "changes, logs and announces nothing when the Feature already reads as that state" do
      expect { set_flag("reviews", { state: "live" }) }
        .to not_change(BotJob, :count).and not_change(FeatureFlagChange, :count)

      expect(response).to have_http_status(:ok)
      expect(json.fetch("meta")).to eq("changed" => false)
      expect(json.dig("data", "state")).to eq("live")
    end

    it "treats a Feature with no stored state as Preview", feature_flags: :none do
      expect { set_flag("reviews", { state: "preview" }) }.not_to change(FeatureFlagChange, :count)
      expect(json.fetch("meta")).to eq("changed" => false)

      set_flag("reviews", { state: "live" })
      expect(json.dig("data", "last_change")).to include("from_state" => "preview", "to_state" => "live")
      expect(BotJob.last.payload).to include("from_state" => "preview", "to_state" => "live")
    end

    it "logs and announces without a reason" do
      set_flag("suggestions", { state: "off" })

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "last_change", "reason")).to be_nil
      expect(BotJob.last.payload).to include("reason" => nil)
    end

    it "is allowed for a Superadmin" do
      superadmin = create(:user, role_member: true)

      set_flag("giveaways", { state: "preview" }, headers: auth_headers_for(superadmin, is_dev: true))

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "last_change", "changed_by")).to eq(superadmin.user_id)
    end

    it "is forbidden for Moderators and members, and changes nothing" do
      [ create(:user, role_moderator: true), create(:user, role_member: true) ].each do |user|
        expect { set_flag("giveaways", { state: "off" }, headers: auth_headers_for(user)) }
          .to not_change(BotJob, :count).and not_change(FeatureFlagChange, :count)
        expect(response).to have_http_status(:forbidden)
      end
      expect(Features.state("giveaways")).to eq("live")
    end

    it "rejects a key that is not a Feature" do
      set_flag("dashboard", { state: "off" })

      expect(response).to have_http_status(:not_found)
      expect(json).to eq("error" => "not_found")
    end

    it "rejects an invalid or missing state, and a reason over 500 characters" do
      [ { state: "enabled" }, { reason: "no state" }, { state: "off", reason: "x" * 501 } ].each do |data|
        expect { set_flag("reviews", data) }.not_to change(FeatureFlagChange, :count)
        expect(response).to have_http_status(:unprocessable_content), "#{data} got #{response.status}"
      end
    end

    describe "from the bot" do
      it "applies the Admin/Superadmin rule to the acting Discord user and logs them as the changer" do
        superadmin = create(:user, role_dev: true, username: "dev_one")

        set_flag("journals", { state: "preview", acting_user_id: superadmin.user_id }, headers: service_headers)

        expect(response).to have_http_status(:ok)
        expect(json.dig("data", "last_change")).to include("changed_by" => superadmin.user_id,
          "changed_by_name" => "dev_one")
        expect(BotJob.last.requested_by_user_id).to eq(superadmin.user_id)
      end

      it "is forbidden when the acting Discord user is not staff" do
        moderator = create(:user, role_moderator: true)

        expect { set_flag("journals", { state: "off", acting_user_id: moderator.user_id }, headers: service_headers) }
          .not_to change(FeatureFlagChange, :count)
        expect(response).to have_http_status(:forbidden)
      end

      it "is a bad request without the acting Discord user" do
        set_flag("journals", { state: "off" }, headers: service_headers)

        expect(response).to have_http_status(:bad_request)
      end
    end

    describe "Achievement Hub coming back from Off" do
      include ActiveJob::TestHelper

      it "starts achievement sync at once, and only when leaving Off" do
        set_feature_flag("achievement_hub", "off")

        expect { set_flag("achievement_hub", { state: "preview" }) }
          .to have_enqueued_job(Achievements::ProviderTickJob).exactly(UserLinkedAccount::PROVIDERS.size).times
        expect { set_flag("achievement_hub", { state: "live" }) }.not_to have_enqueued_job(Achievements::ProviderTickJob)
      end
    end
  end
end
