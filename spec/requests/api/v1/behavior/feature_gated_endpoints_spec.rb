# frozen_string_literal: true

require "rails_helper"

# Every endpoint that belongs to a Feature is behind the feature gate (spec
# #347, ticket #349): a member-token request for a Feature the member cannot
# use gets 404. Each Feature is exercised through one of its real endpoints,
# and every routed controller is checked to declare the Feature it belongs to,
# or to belong to none.
RSpec.describe "feature-gated endpoints", type: :request do
  # One real endpoint per Feature, readable by a plain member when Live.
  endpoints = {
    "game_index" => ->(_user) { "/api/v1/games" },
    "voting_gotm" => ->(_user) { "/api/v1/gotm_rounds" },
    "backlog" => ->(user) { "/api/v1/users/#{user.user_id}/backlog" },
    "collection" => ->(user) { "/api/v1/users/#{user.user_id}/collections" },
    "now_playing" => ->(user) { "/api/v1/users/#{user.user_id}/now_playing" },
    "game_completions" => ->(user) { "/api/v1/users/#{user.user_id}/completions" },
    "reviews" => ->(user) { "/api/v1/users/#{user.user_id}/reviews" },
    "achievement_hub" => ->(_user) { "/api/v1/achievements/feed" },
    "giveaways" => ->(user) { "/api/v1/users/#{user.user_id}/giveaway_settings" },
    "journals" => ->(user) { "/api/v1/users/#{user.user_id}/journal" },
    "suggestions" => ->(_user) { "/api/v1/suggestions" }
  }

  it "covers every registered Feature" do
    expect(endpoints.keys).to match_array(Features.keys)
  end

  endpoints.each do |key, path_for|
    describe "#{key} (#{Features.fetch(key).name})" do
      let(:member) { create(:user, role_member: true) }
      let(:admin) { create(:user, role_admin: true) }

      it "answers a member when Live" do
        get path_for.call(member), headers: auth_headers_for(member)

        expect(response).to have_http_status(:ok)
      end

      it "is not found for a member in Preview and Off" do
        %w[preview off].each do |state|
          set_feature_flag(key, state)
          get path_for.call(member), headers: auth_headers_for(member)

          expect(response).to have_http_status(:not_found), "member got #{response.status} in #{state}"
        end
      end

      it "answers staff in Preview, as Admin and as Superadmin" do
        set_feature_flag(key, "preview")

        get path_for.call(admin), headers: auth_headers_for(admin)
        expect(response).to have_http_status(:ok)

        get path_for.call(member), headers: auth_headers_for(member, is_dev: true)
        expect(response).to have_http_status(:ok)
      end

      it "is not found for staff when Off" do
        set_feature_flag(key, "off")

        get path_for.call(admin), headers: auth_headers_for(admin)

        expect(response).to have_http_status(:not_found)
      end

      it "answers the bot's service token when Off" do
        set_feature_flag(key, "off")

        get path_for.call(member), headers: service_headers

        expect(response).to have_http_status(:ok)
      end
    end
  end

  describe "the logged-out landing page's winners" do
    it "follows Voting & GOTM's flag" do
      get "/api/v1/public/winners"
      expect(response).to have_http_status(:ok)

      set_feature_flag("voting_gotm", "preview")
      get "/api/v1/public/winners"
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "an endpoint that belongs to no Feature" do
    it "answers whatever the Feature Flags say" do
      user = create(:user, role_member: true)
      set_all_feature_flags("off")

      get "/api/v1/session", headers: auth_headers_for(user)
      expect(response).to have_http_status(:ok)

      get "/api/v1/users/#{user.user_id}", headers: auth_headers_for(user)
      expect(response).to have_http_status(:ok)

      get "/api/v1/dashboard", headers: auth_headers_for(user)
      expect(response).to have_http_status(:ok)
    end
  end

  # Which Feature each routed controller's endpoints belong to; nil for the
  # endpoints that are not part of any Feature (spec #347: the dashboard,
  # members and profiles, sign-in, the staff desk, bot utilities) and for the
  # shared lookups other Features' pickers depend on.
  declared = {
    # Game Index
    "api/v1/games" => "game_index",
    "api/v1/game_images" => "game_index",
    "api/v1/game_alternates" => "game_index",
    "api/v1/game_hltb" => "game_index",
    "api/v1/releases" => "game_index",
    # Voting & GOTM
    "api/v1/gotm_rounds" => "voting_gotm",
    "api/v1/gotm_entries" => "voting_gotm",
    "api/v1/nr_gotm_entries" => "voting_gotm",
    "api/v1/nominations" => "voting_gotm",
    "api/v1/votes" => "voting_gotm",
    "api/v1/voting_rounds" => "voting_gotm",
    "api/v1/voting_events" => "voting_gotm",
    "api/v1/voting_info" => "voting_gotm",
    "api/v1/public/winners" => "voting_gotm",
    # Backlog
    "api/v1/backlog" => "backlog",
    # Collection
    "api/v1/collections" => "collection",
    "api/v1/collection_csv_imports" => "collection",
    "api/v1/collection_csv_import_items" => "collection",
    "api/v1/steam_collection_imports" => "collection",
    "api/v1/steam_collection_import_items" => "collection",
    "api/v1/steam_app_gamedb_maps" => "collection",
    # Now Playing
    "api/v1/now_playing" => "now_playing",
    # Game Completions
    "api/v1/completions" => "game_completions",
    "api/v1/completionator_imports" => "game_completions",
    "api/v1/completionator_import_items" => "game_completions",
    # Reviews
    "api/v1/reviews" => "reviews",
    # Achievement Hub
    "api/v1/achievements" => "achievement_hub",
    "api/v1/achievement_sets" => "achievement_hub",
    "api/v1/member_achievements" => "achievement_hub",
    "api/v1/linked_accounts" => "achievement_hub",
    "api/v1/achievement_highlights" => "achievement_hub",
    # Giveaways
    "api/v1/game_keys" => "giveaways",
    "api/v1/giveaway_settings" => "giveaways",
    # Journals
    "api/v1/journal" => "journals",
    "api/v1/journal_message_contexts" => "journals",
    # Suggestions
    "api/v1/suggestions" => "suggestions",
    "api/v1/suggestion_review_sessions" => "suggestions",
    # Not part of any Feature.
    "api/v1/health" => nil,
    "api/v1/sessions" => nil,
    "api/v1/dashboards" => nil,
    "api/v1/users" => nil,
    "api/v1/feature_access" => nil,
    "api/v1/features" => nil,
    "api/v1/feature_preferences" => nil,
    "api/v1/user_roles" => nil,
    "api/v1/user_avatar_history" => nil,
    "api/v1/user_nick_history" => nil,
    "api/v1/user_socials" => nil,
    "api/v1/social_platforms" => nil,
    "api/v1/favorites" => nil,
    "api/v1/wizard_sessions" => nil,
    "api/v1/presence_prompts" => nil,
    "api/v1/presence_prompt_opts" => nil,
    "api/v1/igdb" => nil,
    "api/v1/platforms" => nil,
    "api/v1/regions" => nil,
    "api/v1/genres" => nil,
    "api/v1/themes" => nil,
    "api/v1/perspectives" => nil,
    "api/v1/modes" => nil,
    "api/v1/franchises" => nil,
    "api/v1/companies" => nil,
    "api/v1/engines" => nil,
    "api/v1/threads" => nil,
    "api/v1/thread_game_links" => nil,
    "api/v1/release_announcements" => nil,
    "api/v1/rss_feeds" => nil,
    "api/v1/rss_feed_items" => nil,
    "api/v1/public_reminders" => nil,
    "api/v1/starboard" => nil,
    "api/v1/bot_jobs" => nil,
    "api/v1/bot_presence" => nil,
    "api/v1/bot_say" => nil,
    "api/v1/memberscan" => nil,
    "api/v1/guild_channels" => nil,
    "api/v1/image_backfill_runs" => nil,
    "api/v1/live_events" => nil,
    "api/v1/search_synonyms" => nil,
    "api/v1/search_synonym_groups" => nil,
    "api/v1/search_synonym_drafts" => nil
  }

  it "has every routed controller declare the Feature it belongs to, or none" do
    routed = Rails.application.routes.routes.filter_map { |route| route.defaults[:controller] }
      .grep(%r{\Aapi/v1/}).uniq

    expect(routed).to match_array(declared.keys)
    routed.each do |controller|
      klass = "#{controller.camelize}Controller".constantize
      expect(klass.feature_key).to eq(declared.fetch(controller)), "#{controller} declares #{klass.feature_key.inspect}"
    end
  end
end
