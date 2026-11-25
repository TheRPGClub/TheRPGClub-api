# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_11_25_160500) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "_rpg_club_users_socials_backup", id: false, force: :cascade do |t|
    t.string "completionator_url", limit: 512
    t.string "nsw_friend_code", limit: 50
    t.string "psn_username", limit: 100
    t.string "steam_url", limit: 512
    t.string "user_id", limit: 30
    t.string "xbl_username", limit: 100
  end

  create_table "achievement_hub_states", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "key", limit: 100, null: false
    t.datetime "updated_at", null: false
    t.jsonb "value"
    t.index ["key"], name: "ux_achievement_hub_states_key", unique: true
  end

  create_table "achievement_sets", force: :cascade do |t|
    t.integer "achievements_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "definitions_synced_at"
    t.string "external_id", limit: 64, null: false
    t.bigint "game_id"
    t.string "icon_url", limit: 1024
    t.string "np_service_name", limit: 32
    t.string "platform_label", limit: 100
    t.integer "points_total", default: 0, null: false
    t.string "provider", limit: 32, null: false
    t.string "title", limit: 512
    t.datetime "updated_at", null: false
    t.index ["game_id"], name: "ix_achievement_sets_game"
    t.index ["provider", "external_id"], name: "ux_achievement_sets_provider_external", unique: true
  end

  create_table "achievements", force: :cascade do |t|
    t.bigint "achievement_set_id", null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.integer "display_order"
    t.string "external_id", limit: 64, null: false
    t.boolean "hidden", default: false, null: false
    t.string "icon_locked_url", limit: 1024
    t.string "icon_url", limit: 1024
    t.string "name", limit: 512
    t.integer "points"
    t.decimal "rarity", precision: 5, scale: 2
    t.decimal "rarity_hardcore", precision: 5, scale: 2
    t.datetime "removed_at"
    t.string "tier", limit: 16
    t.datetime "updated_at", null: false
    t.index ["achievement_set_id", "external_id"], name: "ux_achievements_set_external", unique: true
  end

  create_table "birthday_posts", comment: "Each member's Birthday Post, at most one per calendar year.", force: :cascade do |t|
    t.string "user_id", limit: 30, null: false
    t.integer "year", limit: 2, null: false, comment: "The calendar year of the club day it was queued for."
    t.date "posted_on", null: false, comment: "The club day (America/New_York) it was queued for."
    t.timestamptz "created_at", default: -> { "statement_timestamp()" }, null: false
    t.index ["user_id", "year"], name: "ux_birthday_posts_once", unique: true
  end

  create_table "bot_jobs", force: :cascade do |t|
    t.integer "attempts", default: 0, null: false
    t.datetime "claimed_at"
    t.datetime "created_at", null: false
    t.text "error_message"
    t.datetime "finished_at"
    t.string "kind", limit: 64, null: false
    t.datetime "lease_expires_at"
    t.jsonb "payload", default: {}, null: false
    t.string "requested_by_user_id", limit: 30
    t.text "result_text"
    t.string "status", limit: 16, default: "queued", null: false
    t.string "summary", limit: 200, default: "", null: false
    t.datetime "updated_at", null: false
    t.index "((payload ->> 'message_id'::text))", name: "ux_bot_jobs_one_open_news_images_renew", unique: true, where: "(((kind)::text = 'news_images_renew'::text) AND ((status)::text = ANY ((ARRAY['queued'::character varying, 'claimed'::character varying])::text[])))"
    t.index "((payload ->> 'message_id'::text)), finished_at", name: "ix_bot_jobs_finished_news_images_renew", where: "(((kind)::text = 'news_images_renew'::text) AND ((status)::text = ANY ((ARRAY['done'::character varying, 'failed'::character varying])::text[])))"
    t.index ["id"], name: "ix_bot_jobs_queued", where: "((status)::text = 'queued'::text)"
    t.index ["lease_expires_at"], name: "ix_bot_jobs_claimed", where: "((status)::text = 'claimed'::text)"
    t.index ["requested_by_user_id"], name: "index_bot_jobs_on_requested_by_user_id"
    t.check_constraint "status::text = ANY (ARRAY['queued'::character varying, 'claimed'::character varying, 'done'::character varying, 'failed'::character varying]::text[])", name: "ck_bot_jobs_status"
  end

  create_table "bot_presence_history", force: :cascade do |t|
    t.string "activity_name", limit: 1020, null: false
    t.datetime "set_at", default: -> { "statement_timestamp()" }, null: false
    t.string "set_by_user_id", limit: 128
    t.string "set_by_username", limit: 256
    t.index ["set_at"], name: "ix_bot_presence_history_set_at"
  end

  create_table "bot_voting_info", id: false, force: :cascade do |t|
    t.boolean "five_day_reminder_sent", default: false, null: false
    t.datetime "next_vote_at", precision: 0, null: false
    t.bigint "nomination_list_id"
    t.boolean "one_day_reminder_sent", default: false, null: false
    t.bigint "round_number", null: false
    t.datetime "vote_ends_at"
    t.index ["round_number"], name: "ix_bot_voting_info_round"
  end

  create_table "challenge_edition_signups", force: :cascade do |t|
    t.bigint "edition_id", null: false
    t.string "user_id", limit: 30, null: false
    t.timestamptz "signed_up_at", default: -> { "statement_timestamp()" }, null: false
    t.timestamptz "left_out_at"
    t.string "recipient_user_id", limit: 30
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "picked_game_id"
    t.timestamptz "picked_at"
    t.boolean "picked_randomly", default: false, null: false
    t.timestamptz "withdrawn_at"
    t.index ["edition_id", "recipient_user_id"], name: "ux_challenge_edition_signups_recipient", unique: true, where: "(recipient_user_id IS NOT NULL)"
    t.index ["edition_id", "user_id"], name: "ux_challenge_edition_signups_member", unique: true
    t.index ["user_id"], name: "ix_challenge_edition_signups_user"
  end

  create_table "challenge_editions", force: :cascade do |t|
    t.bigint "challenge_id", null: false
    t.integer "year", null: false
    t.string "phase", limit: 16, default: "signup", null: false
    t.date "signup_opens_on", null: false
    t.date "signup_cutoff_on", null: false
    t.date "pick_deadline_on", null: false
    t.date "reveal_on", null: false
    t.date "ends_on", null: false
    t.timestamptz "drawn_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.timestamptz "picks_closed_at"
    t.string "signup_post_channel_id", limit: 30
    t.string "signup_post_message_id", limit: 30
    t.index ["challenge_id", "year"], name: "ux_challenge_editions_year", unique: true
    t.index ["phase", "signup_cutoff_on"], name: "ix_challenge_editions_phase"
    t.check_constraint "phase::text = ANY (ARRAY['signup'::character varying, 'picking'::character varying, 'revealed'::character varying, 'ended'::character varying, 'cancelled'::character varying]::text[])", name: "ck_challenge_editions_phase"
    t.check_constraint "signup_opens_on < signup_cutoff_on AND signup_cutoff_on < pick_deadline_on AND pick_deadline_on < reveal_on AND reveal_on < ends_on", name: "ck_challenge_editions_dates"
    t.check_constraint "(signup_post_channel_id IS NULL) = (signup_post_message_id IS NULL)", name: "ck_challenge_editions_signup_post"
  end

  create_table "challenge_finish_announcements", primary_key: ["challenge_id", "user_id", "season_starts_on"], force: :cascade do |t|
    t.bigint "challenge_id", null: false
    t.string "user_id", limit: 30, null: false
    t.date "season_starts_on", null: false
    t.timestamptz "announced_at", default: -> { "statement_timestamp()" }, null: false
  end

  create_table "challenge_lifecycle_steps", force: :cascade do |t|
    t.bigint "challenge_id", null: false
    t.string "step", limit: 48, null: false
    t.date "occurs_on", null: false
    t.timestamptz "done_at", default: -> { "statement_timestamp()" }, null: false
    t.index ["challenge_id", "step", "occurs_on"], name: "ux_challenge_lifecycle_steps_once", unique: true
  end

  create_table "challenge_pool_collections", primary_key: ["challenge_id", "collection_id"], force: :cascade do |t|
    t.bigint "challenge_id", null: false
    t.bigint "collection_id", null: false
  end

  create_table "challenge_pool_franchises", primary_key: ["challenge_id", "franchise_id"], force: :cascade do |t|
    t.bigint "challenge_id", null: false
    t.bigint "franchise_id", null: false
  end

  create_table "challenge_pool_games", primary_key: ["challenge_id", "game_id"], force: :cascade do |t|
    t.bigint "challenge_id", null: false
    t.bigint "game_id", null: false
    t.string "inclusion", limit: 8, null: false
    t.datetime "added_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.check_constraint "inclusion::text = ANY (ARRAY['core'::character varying, 'optional'::character varying, 'exclude'::character varying]::text[])", name: "ck_challenge_pool_games_inclusion"
  end

  create_table "challenge_pool_list_notices", force: :cascade do |t|
    t.bigint "challenge_id", null: false
    t.bigint "game_id", null: false
    t.timestamptz "created_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.index ["challenge_id", "game_id"], name: "ux_challenge_pool_list_notices", unique: true
    t.index ["game_id"], name: "ix_challenge_pool_list_notices_game"
  end

  create_table "challenge_pool_proposals", force: :cascade do |t|
    t.bigint "challenge_id", null: false
    t.bigint "game_id", null: false
    t.string "user_id", limit: 30, null: false
    t.string "note", limit: 280
    t.string "status", limit: 16, default: "pending", null: false
    t.string "accepted_as", limit: 16
    t.string "decided_by", limit: 30
    t.timestamptz "decided_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["challenge_id", "game_id"], name: "ux_challenge_pool_proposals_one_pending", unique: true, where: "((status)::text = 'pending'::text)"
    t.index ["challenge_id", "status", "created_at"], name: "ix_challenge_pool_proposals_challenge"
    t.index ["user_id"], name: "ix_challenge_pool_proposals_user"
    t.check_constraint "(status::text = 'accepted'::text) = (accepted_as IS NOT NULL) AND (accepted_as IS NULL OR (accepted_as::text = ANY (ARRAY['core'::character varying, 'optional'::character varying]::text[])))", name: "ck_challenge_pool_proposals_accepted_as"
    t.check_constraint "(status::text = 'pending'::text) = (decided_at IS NULL)", name: "ck_challenge_pool_proposals_decided"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying, 'accepted'::character varying, 'declined'::character varying]::text[])", name: "ck_challenge_pool_proposals_status"
  end

  create_table "challenge_run_entries", force: :cascade do |t|
    t.bigint "run_id", null: false
    t.bigint "game_id", null: false
    t.string "state", limit: 16, null: false
    t.bigint "completion_id"
    t.date "cleared_on"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "slot_year", limit: 2
    t.boolean "picked_by_hand", default: false, null: false
    t.index ["cleared_on", "id"], name: "ix_challenge_run_entries_cleared", where: "(((state)::text = 'cleared'::text) AND (cleared_on IS NOT NULL))"
    t.index ["run_id", "game_id"], name: "ux_challenge_run_entries_game", unique: true
    t.check_constraint "slot_year IS NULL OR state::text = 'cleared'::text", name: "ck_challenge_run_entries_slot_cleared"
    t.check_constraint "state::text = ANY (ARRAY['in_progress'::character varying, 'cleared'::character varying]::text[])", name: "ck_challenge_run_entries_state"
  end

  create_table "challenge_runs", force: :cascade do |t|
    t.bigint "challenge_id", null: false
    t.string "user_id", limit: 30, null: false
    t.string "status", limit: 16, default: "active", null: false
    t.timestamptz "started_at", default: -> { "statement_timestamp()" }, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.date "season_starts_on"
    t.date "season_ends_on"
    t.timestamptz "ended_at"
    t.integer "first_year", limit: 2
    t.integer "caught_up_announced_year", limit: 2
    t.bigint "edition_id"
    t.index ["challenge_id", "status"], name: "ix_challenge_runs_challenge_status"
    t.index ["challenge_id", "user_id"], name: "ux_challenge_runs_one_active", unique: true, where: "(((status)::text = 'active'::text) AND (edition_id IS NULL))"
    t.index ["edition_id", "user_id"], name: "ux_challenge_runs_edition_member", unique: true, where: "(edition_id IS NOT NULL)"
    t.index ["ended_at", "id"], name: "ix_challenge_runs_finished", where: "(((status)::text = 'finished'::text) AND (ended_at IS NOT NULL))"
    t.index ["started_at", "id"], name: "ix_challenge_runs_started"
    t.index ["user_id"], name: "ix_challenge_runs_user"
    t.check_constraint "(season_starts_on IS NULL) = (season_ends_on IS NULL)", name: "ck_challenge_runs_season"
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying, 'finished'::character varying, 'expired'::character varying, 'abandoned'::character varying]::text[])", name: "ck_challenge_runs_status"
  end

  create_table "challenges", force: :cascade do |t|
    t.string "name", limit: 100, null: false
    t.text "description", default: "", null: false
    t.string "host_user_id", limit: 30
    t.string "challenge_format", limit: 16, null: false
    t.string "schedule", limit: 16, null: false
    t.date "ends_on"
    t.integer "season_start_month", limit: 2
    t.integer "season_start_day", limit: 2
    t.integer "season_end_month", limit: 2
    t.integer "season_end_day", limit: 2
    t.boolean "hidden", default: false, null: false
    t.string "created_by", limit: 30
    t.string "updated_by", limit: 30
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.timestamptz "ended_at", comment: "When the Always Open Challenge reached its end date and Closed for good."
    t.integer "slots_first_year", limit: 2
    t.integer "slots_last_year", limit: 2
    t.integer "signup_cutoff_month", limit: 2
    t.integer "signup_cutoff_day", limit: 2
    t.integer "pick_deadline_month", limit: 2
    t.integer "pick_deadline_day", limit: 2
    t.integer "reveal_month", limit: 2
    t.integer "reveal_day", limit: 2
    t.boolean "counts_past_play", default: false, null: false
    t.string "tint_fill", limit: 7, null: false
    t.string "tint_hi", limit: 7, null: false
    t.integer "pool_optional_target", default: 0, null: false
    t.bigint "pool_game_list_id"
    t.index "lower((name)::text)", name: "ix_challenges_lower_name"
    t.index ["host_user_id"], name: "ix_challenges_host"
    t.index ["pool_game_list_id"], name: "ix_challenges_pool_game_list", where: "(pool_game_list_id IS NOT NULL)"
    t.check_constraint "(schedule::text = 'seasonal'::text) = (season_start_month IS NOT NULL AND season_start_day IS NOT NULL AND season_end_month IS NOT NULL AND season_end_day IS NOT NULL)", name: "ck_challenges_season"
    t.check_constraint "challenge_format::text <> 'assignment'::text OR schedule::text = 'always_open'::text AND ends_on IS NULL", name: "ck_challenges_assignment_schedule"
    t.check_constraint "NOT counts_past_play OR schedule::text = 'always_open'::text", name: "ck_challenges_past_play_always_open"
    t.check_constraint "challenge_format::text = ANY (ARRAY['slots'::character varying, 'pool'::character varying, 'assignment'::character varying]::text[])", name: "ck_challenges_format"
    t.check_constraint "pool_optional_target >= 0", name: "ck_challenges_pool_optional_target"
    t.check_constraint "schedule::text = 'always_open'::text OR ends_on IS NULL", name: "ck_challenges_ends_on"
    t.check_constraint "schedule::text = ANY (ARRAY['always_open'::character varying, 'seasonal'::character varying]::text[])", name: "ck_challenges_schedule"
    t.check_constraint "slots_first_year IS NULL OR slots_last_year IS NULL OR slots_first_year <= slots_last_year", name: "ck_challenges_slots_range"
    t.check_constraint "tint_fill::text ~ '^#[0-9a-f]{6}$'::text AND tint_hi::text ~ '^#[0-9a-f]{6}$'::text", name: "ck_challenges_tint"
  end

  create_table "codex_entries", force: :cascade do |t|
    t.string "part", limit: 16, null: false
    t.string "title", limit: 100
    t.jsonb "rich_body"
    t.text "body"
    t.date "occurred_on"
    t.string "date_precision", limit: 8
    t.string "kind", limit: 16
    t.string "author_user_id", limit: 30, null: false
    t.timestamptz "last_shown_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["author_user_id"], name: "ix_codex_entries_author"
    t.index ["last_shown_at", "id"], name: "ix_codex_entries_fun_fact_queue", where: "((part)::text = 'fun_fact'::text)"
    t.index ["occurred_on", "id"], name: "ix_codex_entries_history", where: "((part)::text = 'history_event'::text)"
    t.index ["part", "created_at", "id"], name: "ix_codex_entries_part_created"
    t.check_constraint "(kind IS NOT NULL) = (part::text = 'history_event'::text)", name: "ck_codex_entries_kind_part"
    t.check_constraint "(occurred_on IS NULL) = (date_precision IS NULL)", name: "ck_codex_entries_date_given_together"
    t.check_constraint "(title IS NOT NULL) = (part::text <> 'fun_fact'::text)", name: "ck_codex_entries_title_part"
    t.check_constraint "date_precision::text <> 'year'::text OR EXTRACT(month FROM occurred_on) = 1::numeric", name: "ck_codex_entries_year_starts"
    t.check_constraint "date_precision::text = 'day'::text OR EXTRACT(day FROM occurred_on) = 1::numeric", name: "ck_codex_entries_month_starts"
    t.check_constraint "date_precision::text = ANY (ARRAY['day'::character varying, 'month'::character varying, 'year'::character varying]::text[])", name: "ck_codex_entries_date_precision"
    t.check_constraint "kind::text = ANY (ARRAY['founding'::character varying, 'staff'::character varying, 'platform'::character varying, 'rules'::character varying, 'milestone'::character varying]::text[])", name: "ck_codex_entries_kind"
    t.check_constraint "part::text <> 'fun_fact'::text OR occurred_on IS NULL", name: "ck_codex_entries_fun_fact_undated"
    t.check_constraint "part::text <> 'fun_fact'::text OR rich_body IS NULL AND char_length(body) <= 300", name: "ck_codex_entries_fun_fact_body"
    t.check_constraint "part::text <> 'history_event'::text OR occurred_on IS NOT NULL", name: "ck_codex_entries_history_dated"
    t.check_constraint "part::text = 'fun_fact'::text OR last_shown_at IS NULL", name: "ck_codex_entries_last_shown_fun_fact"
    t.check_constraint "part::text = 'history_event'::text OR body IS NOT NULL", name: "ck_codex_entries_body_part"
    t.check_constraint "part::text = ANY (ARRAY['history_event'::character varying, 'lore_entry'::character varying, 'fun_fact'::character varying]::text[])", name: "ck_codex_entries_part"
    t.check_constraint "rich_body IS NULL OR body IS NOT NULL", name: "ck_codex_entries_body_with_rich_body"
  end

  create_table "codex_entry_images", force: :cascade do |t|
    t.bigint "entry_id", null: false
    t.string "object_key", null: false
    t.integer "position", limit: 2, null: false
    t.string "uploaded_by_user_id", limit: 30, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["object_key"], name: "ux_codex_entry_images_object_key", unique: true
    t.index ["uploaded_by_user_id"], name: "ix_codex_entry_images_uploader"
    t.check_constraint "\"position\" >= 1 AND \"position\" <= 4", name: "ck_codex_entry_images_position"
    t.unique_constraint ["entry_id", "position"], deferrable: :deferred, name: "uq_codex_entry_images_entry_position"
  end

  create_table "codex_entry_links", primary_key: ["low_entry_id", "high_entry_id"], force: :cascade do |t|
    t.bigint "low_entry_id", null: false
    t.bigint "high_entry_id", null: false
    t.timestamptz "created_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.index ["high_entry_id"], name: "ix_codex_entry_links_high"
    t.check_constraint "low_entry_id < high_entry_id", name: "ck_codex_entry_links_ordered_pair"
  end

  create_table "codex_entry_mentions", primary_key: ["entry_id", "user_id"], force: :cascade do |t|
    t.bigint "entry_id", null: false
    t.string "user_id", limit: 30, null: false
    t.index ["user_id"], name: "ix_codex_entry_mentions_user"
  end

  create_table "daily_fun_fact_posts", comment: "The Fun Fact queued as each club day's Daily Fun Fact.", force: :cascade do |t|
    t.date "club_date", null: false, comment: "The club day (America/New_York) it was queued for."
    t.bigint "entry_id", comment: "The Fun Fact posted; null once it is deleted, so the day stays posted."
    t.timestamptz "created_at", default: -> { "statement_timestamp()" }, null: false
    t.index ["club_date"], name: "ux_daily_fun_fact_posts_club_date", unique: true
    t.index ["entry_id"], name: "ix_daily_fun_fact_posts_entry"
  end

  create_table "feature_flag_changes", force: :cascade do |t|
    t.string "feature_key", limit: 64, null: false
    t.string "from_state", limit: 16
    t.string "to_state", limit: 16, null: false
    t.string "changed_by", limit: 30, null: false
    t.text "reason"
    t.datetime "created_at", null: false
    t.index ["feature_key", "created_at"], name: "index_feature_flag_changes_on_feature_key_and_created_at"
    t.check_constraint "from_state IS NULL OR (from_state::text = ANY (ARRAY['off'::character varying, 'preview'::character varying, 'live'::character varying]::text[]))", name: "ck_feature_flag_changes_from_state"
    t.check_constraint "to_state::text = ANY (ARRAY['off'::character varying, 'preview'::character varying, 'live'::character varying]::text[])", name: "ck_feature_flag_changes_to_state"
  end

  create_table "feature_flags", force: :cascade do |t|
    t.string "key", limit: 64, null: false
    t.string "state", limit: 16, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_feature_flags_on_key", unique: true
    t.check_constraint "state::text = ANY (ARRAY['off'::character varying, 'preview'::character varying, 'live'::character varying]::text[])", name: "ck_feature_flags_state"
  end

  create_table "game_list_entries", primary_key: ["game_list_id", "game_id"], force: :cascade do |t|
    t.bigint "game_list_id", null: false
    t.bigint "game_id", null: false
    t.integer "position", null: false
    t.string "note", limit: 280
    t.timestamptz "added_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.index ["game_id"], name: "ix_game_list_entries_game"
    t.index ["game_list_id", "position"], name: "ix_game_list_entries_position"
    t.check_constraint "\"position\" >= 1", name: "ck_game_list_entries_position"
  end

  create_table "game_lists", force: :cascade do |t|
    t.string "owner_user_id", limit: 30
    t.string "name", limit: 100, null: false
    t.string "description", limit: 500
    t.string "visibility", limit: 8, default: "members", null: false
    t.string "sort", limit: 12, default: "ranked", null: false
    t.string "taken_over_from_user_id", limit: 30
    t.timestamptz "taken_over_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["owner_user_id", "updated_at"], name: "ix_game_lists_owner_updated"
    t.index ["updated_at"], name: "ix_game_lists_updated"
    t.check_constraint "owner_user_id IS NOT NULL OR visibility::text = 'members'::text", name: "ck_game_lists_club_members"
    t.check_constraint "sort::text = ANY (ARRAY['ranked'::character varying, 'alphabetical'::character varying, 'added'::character varying]::text[])", name: "ck_game_lists_sort"
    t.check_constraint "taken_over_from_user_id IS NULL OR taken_over_at IS NOT NULL", name: "ck_game_lists_taken_over_at"
    t.check_constraint "visibility::text = ANY (ARRAY['members'::character varying, 'private'::character varying]::text[])", name: "ck_game_lists_visibility"
  end

  create_table "gamedb_collections", primary_key: "collection_id", force: :cascade do |t|
    t.bigint "igdb_collection_id"
    t.string "name", limit: 255, null: false

    t.unique_constraint ["igdb_collection_id"], name: "gamedb_collections_igdb_collection_id_key"
  end

  create_table "gamedb_companies", primary_key: "company_id", force: :cascade do |t|
    t.bigint "igdb_company_id"
    t.string "name", limit: 255, null: false

    t.unique_constraint ["igdb_company_id"], name: "gamedb_companies_igdb_company_id_key"
  end

  create_table "gamedb_deleted_franchises", primary_key: "igdb_franchise_id", force: :cascade do |t|
    t.string "name", limit: 255, null: false
    t.string "deleted_by", limit: 30
    t.datetime "deleted_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
  end

  create_table "gamedb_engines", primary_key: "engine_id", force: :cascade do |t|
    t.bigint "igdb_engine_id"
    t.string "name", limit: 255, null: false

    t.unique_constraint ["igdb_engine_id"], name: "gamedb_engines_igdb_engine_id_key"
  end

  create_table "gamedb_franchise_changes", force: :cascade do |t|
    t.bigint "franchise_id", null: false
    t.bigint "game_id"
    t.string "action", limit: 20, null: false
    t.jsonb "before"
    t.jsonb "after"
    t.string "user_id", limit: 30
    t.datetime "created_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.datetime "undone_at"
    t.string "undone_by", limit: 30
    t.index ["franchise_id", "game_id", "id"], name: "ix_gamedb_franchise_changes_game"
    t.index ["franchise_id", "id"], name: "ix_gamedb_franchise_changes_franchise"
    t.check_constraint "action::text = ANY (ARRAY['link'::character varying, 'unlink'::character varying, 'mainline_on'::character varying, 'mainline_off'::character varying, 'create'::character varying, 'rename'::character varying, 'merge'::character varying, 'delete'::character varying]::text[])", name: "ck_gamedb_franchise_changes_action"
  end

  create_table "gamedb_franchise_unlinks", primary_key: ["game_id", "franchise_id"], force: :cascade do |t|
    t.bigint "game_id", null: false
    t.bigint "franchise_id", null: false
    t.string "unlinked_by", limit: 30
    t.datetime "unlinked_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
  end

  create_table "gamedb_franchises", primary_key: "franchise_id", force: :cascade do |t|
    t.bigint "igdb_franchise_id"
    t.string "name", limit: 255, null: false
    t.string "created_by", limit: 30
    t.boolean "name_locked", default: false, null: false
    t.bigint "merged_into_id"
    t.index ["merged_into_id"], name: "index_gamedb_franchises_on_merged_into_id"
    t.unique_constraint ["igdb_franchise_id"], name: "gamedb_franchises_igdb_franchise_id_key"
  end

  create_table "gamedb_game_alternates", primary_key: ["game_id", "alt_game_id"], force: :cascade do |t|
    t.bigint "alt_game_id", null: false
    t.datetime "created_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.string "created_by", limit: 64
    t.bigint "game_id", null: false
    t.check_constraint "game_id < alt_game_id", name: "ck_gamedb_game_alts_order"
  end

  create_table "gamedb_game_companies", primary_key: ["game_id", "company_id", "role"], force: :cascade do |t|
    t.bigint "company_id", null: false
    t.bigint "game_id", null: false
    t.string "role", limit: 20, null: false
    t.check_constraint "role::text = ANY (ARRAY['Developer'::character varying::text, 'Publisher'::character varying::text])", name: "sys_c009102"
  end

  create_table "gamedb_game_engines", primary_key: ["game_id", "engine_id"], force: :cascade do |t|
    t.bigint "engine_id", null: false
    t.bigint "game_id", null: false
    t.index ["engine_id"], name: "index_gamedb_game_engines_on_engine_id"
    t.index ["game_id"], name: "index_gamedb_game_engines_on_game_id"
  end

  create_table "gamedb_game_franchises", primary_key: ["game_id", "franchise_id"], force: :cascade do |t|
    t.bigint "franchise_id", null: false
    t.bigint "game_id", null: false
    t.string "source", limit: 10, default: "igdb", null: false
    t.boolean "mainline", default: false, null: false
    t.datetime "created_at", default: -> { "CURRENT_TIMESTAMP" }
    t.string "created_by", limit: 30
    t.index ["franchise_id"], name: "index_gamedb_game_franchises_on_franchise_id"
    t.check_constraint "source::text = ANY (ARRAY['igdb'::character varying, 'manual'::character varying]::text[])", name: "ck_gamedb_game_franchises_source"
  end

  create_table "gamedb_game_genres", primary_key: ["game_id", "genre_id"], force: :cascade do |t|
    t.bigint "game_id", null: false
    t.bigint "genre_id", null: false
  end

  create_table "gamedb_game_images", primary_key: "image_id", force: :cascade do |t|
    t.datetime "created_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.bigint "game_id", null: false
    t.boolean "is_primary", default: false, null: false
    t.string "kind", limit: 32, null: false
    t.string "object_key", limit: 512, null: false
    t.integer "position", default: 1, null: false
    t.datetime "updated_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.string "uploaded_by_user_id", limit: 30
    t.index ["game_id", "kind", "position"], name: "idx_gamedb_game_images_lookup"
    t.index ["game_id", "kind"], name: "idx_gamedb_game_images_one_primary", unique: true, where: "(is_primary = true)"
    t.index ["object_key"], name: "index_gamedb_game_images_on_object_key", unique: true
    t.check_constraint "kind::text = ANY (ARRAY['cover'::character varying::text, 'artwork'::character varying::text, 'logo'::character varying::text])", name: "ck_gamedb_game_images_kind"
  end

  create_table "gamedb_game_modes", primary_key: ["game_id", "mode_id"], force: :cascade do |t|
    t.bigint "game_id", null: false
    t.bigint "mode_id", null: false
  end

  create_table "gamedb_game_modes_def", primary_key: "mode_id", force: :cascade do |t|
    t.bigint "igdb_game_mode_id"
    t.string "name", limit: 100, null: false

    t.unique_constraint ["igdb_game_mode_id"], name: "gamedb_game_modes_def_igdb_game_mode_id_key"
  end

  create_table "gamedb_game_perspectives", primary_key: ["game_id", "perspective_id"], force: :cascade do |t|
    t.bigint "game_id", null: false
    t.bigint "perspective_id", null: false
  end

  create_table "gamedb_game_platforms", primary_key: ["game_id", "platform_id"], force: :cascade do |t|
    t.bigint "game_id", null: false
    t.bigint "platform_id", null: false
    t.index ["game_id"], name: "idx_ggp_game"
    t.index ["platform_id"], name: "idx_ggp_platform"
  end

  create_table "gamedb_game_themes", primary_key: ["game_id", "theme_id"], force: :cascade do |t|
    t.bigint "game_id", null: false
    t.bigint "theme_id", null: false
  end

  create_table "gamedb_games", primary_key: "game_id", force: :cascade do |t|
    t.bigint "collection_id"
    t.datetime "created_at", default: -> { "CURRENT_TIMESTAMP" }
    t.text "description"
    t.string "featured_video_url", limit: 512
    t.bigint "igdb_id"
    t.string "igdb_url", limit: 512
    t.datetime "initial_release_date", precision: 0
    t.string "parent_game_name", limit: 255
    t.bigint "parent_igdb_id"
    t.string "slug", limit: 255
    t.boolean "thumbnail_approved", default: false, null: false
    t.boolean "thumbnail_bad", default: false, null: false
    t.string "title", limit: 255, null: false
    t.decimal "total_rating"
    t.datetime "updated_at", default: -> { "CURRENT_TIMESTAMP" }
    t.datetime "release_announced_at"

    t.unique_constraint ["igdb_id"], name: "gamedb_games_igdb_id_key"
  end

  create_table "gamedb_genres", primary_key: "genre_id", force: :cascade do |t|
    t.bigint "igdb_genre_id"
    t.string "name", limit: 100, null: false

    t.unique_constraint ["igdb_genre_id"], name: "gamedb_genres_igdb_genre_id_key"
  end

  create_table "gamedb_perspectives", primary_key: "perspective_id", force: :cascade do |t|
    t.bigint "igdb_perspective_id"
    t.string "name", limit: 100, null: false

    t.unique_constraint ["igdb_perspective_id"], name: "gamedb_perspectives_igdb_perspective_id_key"
  end

  create_table "gamedb_platforms", primary_key: "platform_id", force: :cascade do |t|
    t.bigint "igdb_platform_id"
    t.bigint "igdb_updated_at"
    t.string "platform_abbreviation", limit: 50
    t.string "platform_checksum", limit: 64
    t.string "platform_code", limit: 20, null: false
    t.string "platform_name", limit: 100, null: false
    t.string "platform_slug", limit: 255

    t.unique_constraint ["igdb_platform_id"], name: "gamedb_platforms_igdb_platform_id_key"
    t.unique_constraint ["platform_code"], name: "gamedb_platforms_platform_code_key"
  end

  create_table "gamedb_regions", primary_key: "region_id", force: :cascade do |t|
    t.bigint "igdb_region_id"
    t.string "region_code", limit: 10, null: false
    t.string "region_name", limit: 100, null: false

    t.unique_constraint ["igdb_region_id"], name: "gamedb_regions_igdb_region_id_key"
    t.unique_constraint ["region_code"], name: "gamedb_regions_region_code_key"
  end

  create_table "gamedb_release_announcements", primary_key: "release_id", id: :bigint, default: nil, force: :cascade do |t|
    t.datetime "announce_at", precision: 0, null: false
    t.datetime "created_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.datetime "sent_at"
    t.string "skip_reason", limit: 80
    t.datetime "skipped_at"
    t.datetime "updated_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.index ["sent_at", "skipped_at", "announce_at"], name: "idx_gamedb_release_announce_pending"
  end

  create_table "gamedb_releases", primary_key: "release_id", force: :cascade do |t|
    t.string "format", limit: 20
    t.bigint "game_id", null: false
    t.string "notes", limit: 255
    t.bigint "platform_id", null: false
    t.bigint "region_id", null: false
    t.date "release_date"
    t.string "source", limit: 10, default: "manual", null: false
    t.string "date_precision", limit: 10, default: "day", null: false
    t.index ["game_id"], name: "idx_gamedb_releases_game"
    t.index ["platform_id"], name: "idx_gamedb_releases_platform"
    t.index ["region_id"], name: "idx_gamedb_releases_region"
    t.check_constraint "(date_precision::text = 'tba'::text) = (release_date IS NULL)", name: "ck_gamedb_releases_tba_has_no_date"
    t.check_constraint "date_precision::text = ANY (ARRAY['day'::character varying, 'month'::character varying, 'quarter'::character varying, 'year'::character varying, 'tba'::character varying]::text[])", name: "ck_gamedb_releases_date_precision"
    t.check_constraint "format::text = ANY (ARRAY['Physical'::character varying::text, 'Digital'::character varying::text])", name: "sys_c009076"
    t.check_constraint "source::text = ANY (ARRAY['igdb'::character varying, 'manual'::character varying]::text[])", name: "ck_gamedb_releases_source"
  end

  create_table "gamedb_search_synonym_drafts", primary_key: "draft_id", force: :cascade do |t|
    t.datetime "created_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.text "pairs_json"
    t.datetime "updated_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.string "user_id", limit: 64, null: false
  end

  create_table "gamedb_search_synonym_groups", primary_key: "group_id", force: :cascade do |t|
    t.datetime "created_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.string "created_by", limit: 64
  end

  create_table "gamedb_search_synonyms", primary_key: "term_id", force: :cascade do |t|
    t.datetime "created_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.string "created_by", limit: 64
    t.bigint "group_id", null: false
    t.string "term_norm", limit: 255, null: false
    t.string "term_text", limit: 255, null: false
    t.index ["group_id"], name: "idx_gamedb_search_synonyms_group"
    t.unique_constraint ["group_id", "term_norm"], name: "gamedb_search_synonyms_group_id_term_norm_key"
  end

  create_table "gamedb_themes", primary_key: "theme_id", force: :cascade do |t|
    t.bigint "igdb_theme_id"
    t.string "name", limit: 100, null: false

    t.unique_constraint ["igdb_theme_id"], name: "gamedb_themes_igdb_theme_id_key"
  end

  create_table "gotm_entries", primary_key: "gotm_id", force: :cascade do |t|
    t.integer "game_index", limit: 2, null: false
    t.bigint "gamedb_game_id"
    t.string "month_year", limit: 200, null: false
    t.string "reddit_url", limit: 2048
    t.integer "round_number", null: false
    t.string "voting_results_message_id", limit: 200
    t.index ["gamedb_game_id"], name: "idx_gotm_entries_game"
    t.index ["month_year"], name: "ix_gotm_month_year"
    t.index ["round_number", "game_index"], name: "uk_gotm_round_idx", unique: true
    t.index ["round_number"], name: "ix_gotm_round"
  end

  create_table "gotm_nominations", primary_key: "nomination_id", force: :cascade do |t|
    t.bigint "gamedb_game_id"
    t.datetime "nominated_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.string "reason", limit: 1500
    t.bigint "round_number", null: false
    t.string "user_id", limit: 64, null: false
    t.index ["round_number", "user_id"], name: "ux_gotm_nominations_round_user", unique: true
    t.index ["round_number"], name: "ix_gotm_nominations_round"
  end

  create_table "gotm_votes", primary_key: "vote_id", force: :cascade do |t|
    t.bigint "gamedb_game_id", null: false
    t.bigint "nomination_id", null: false
    t.bigint "round_number", null: false
    t.boolean "runoff", default: false, null: false
    t.string "user_id", limit: 64, null: false
    t.datetime "voted_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.index ["round_number", "nomination_id"], name: "ix_gotm_votes_round_nomination"
    t.index ["round_number", "runoff", "user_id", "gamedb_game_id"], name: "ux_gotm_votes_round_runoff_user_game", unique: true
  end

  create_table "guild_channels", primary_key: "channel_id", id: :string, force: :cascade do |t|
    t.integer "channel_type", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.string "parent_id"
    t.integer "position", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["channel_type", "parent_id", "position"], name: "ix_guild_channels_type_parent_position"
  end

  create_table "help", primary_key: ["topic", "seq"], force: :cascade do |t|
    t.string "info", limit: 80
    t.bigint "seq", null: false
    t.string "topic", limit: 50, null: false
  end

  create_table "image_backfill_runs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "done", default: 0, null: false
    t.integer "failed", default: 0, null: false
    t.datetime "finished_at"
    t.text "last_error"
    t.integer "skipped", default: 0, null: false
    t.datetime "started_at"
    t.string "started_by_user_id", limit: 30
    t.string "status", limit: 16, default: "queued", null: false
    t.integer "total", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["status"], name: "ix_image_backfill_runs_one_in_progress", unique: true, where: "((status)::text = ANY ((ARRAY['queued'::character varying, 'running'::character varying])::text[]))"
    t.check_constraint "status::text = ANY (ARRAY['queued'::character varying, 'running'::character varying, 'completed'::character varying, 'failed'::character varying]::text[])", name: "ck_image_backfill_runs_status"
  end

  create_table "journal_message_contexts", primary_key: ["channel_id", "message_id"], force: :cascade do |t|
    t.string "channel_id", limit: 30, null: false
    t.bigint "created_at_ms", null: false
    t.bigint "game_id", null: false
    t.string "message_id", limit: 30, null: false
    t.string "owner_user_id", limit: 30, null: false
  end

  create_table "live_events", force: :cascade do |t|
    t.bigint "bot_job_id"
    t.datetime "created_at", null: false
    t.string "created_by_user_id", limit: 30
    t.string "discord_event_id", limit: 30
    t.string "discord_thread_id", limit: 30
    t.datetime "ends_at", null: false
    t.text "image_url"
    t.datetime "starts_at", null: false
    t.string "status", limit: 16, default: "queued", null: false
    t.string "topic", limit: 100, null: false
    t.datetime "updated_at", null: false
    t.index ["bot_job_id"], name: "index_live_events_on_bot_job_id"
    t.index ["created_at"], name: "index_live_events_on_created_at"
    t.check_constraint "ends_at > starts_at", name: "ck_live_events_ends_after_start"
    t.check_constraint "status::text = ANY (ARRAY['queued'::character varying, 'thread_created'::character varying, 'created'::character varying, 'failed'::character varying]::text[])", name: "ck_live_events_status"
  end

  create_table "member_birth_date_changes", force: :cascade do |t|
    t.string "user_id", limit: 30, null: false
    t.string "changed_by", limit: 30, comment: "Discord user id of whoever changed it; null for the bot."
    t.boolean "by_staff", default: false, null: false, comment: "Changed by staff, which doesn't count toward the member's limit."
    t.datetime "changed_at", null: false
    t.integer "birth_month", limit: 2, comment: "The Birth Date it was set to (null when removed): its month, 1 to 12."
    t.integer "birth_day", limit: 2, comment: "The Birth Date it was set to (null when removed): its day of the month (29 February allowed without a year)."
    t.integer "birth_year", limit: 2, comment: "The Birth Date it was set to (null when removed): its year, or null when the member gave only the day and month."
    t.index ["user_id", "changed_at"], name: "index_member_birth_date_changes_on_user_id_and_changed_at"
    t.check_constraint "birth_month IS NULL AND birth_day IS NULL AND birth_year IS NULL OR birth_month IS NOT NULL AND birth_day IS NOT NULL AND birth_month >= 1 AND birth_month <= 12 AND birth_day >= 1 AND birth_day <=\nCASE\n    WHEN birth_month = 2 THEN 29\n    WHEN birth_month = ANY (ARRAY[4, 6, 9, 11]) THEN 30\n    ELSE 31\nEND", name: "ck_member_birth_date_changes_birth_date"
  end

  create_table "member_dashboard_panels", force: :cascade do |t|
    t.string "user_id", limit: 30, null: false
    t.string "panel_key", limit: 64, null: false
    t.integer "position", null: false
    t.datetime "created_at", null: false
    t.index ["user_id", "panel_key"], name: "index_member_dashboard_panels_on_user_id_and_panel_key", unique: true
  end

  create_table "member_feature_preferences", force: :cascade do |t|
    t.string "user_id", limit: 30, null: false
    t.string "feature_key", limit: 64, null: false
    t.datetime "created_at", null: false
    t.index ["user_id", "feature_key"], name: "index_member_feature_preferences_on_user_id_and_feature_key", unique: true
  end

  create_table "member_hidden_platforms", force: :cascade do |t|
    t.string "user_id", limit: 30, null: false
    t.bigint "platform_id", null: false
    t.datetime "created_at", null: false
    t.index ["platform_id"], name: "index_member_hidden_platforms_on_platform_id"
    t.index ["user_id", "platform_id"], name: "index_member_hidden_platforms_on_user_id_and_platform_id", unique: true
  end

  create_table "member_news_category_preferences", force: :cascade do |t|
    t.string "category_key", limit: 64, null: false
    t.datetime "created_at", null: false
    t.string "user_id", limit: 30, null: false
    t.index ["user_id", "category_key"], name: "index_member_news_category_preferences_on_user_and_category", unique: true
  end

  create_table "member_pinned_pages", force: :cascade do |t|
    t.string "user_id", limit: 30, null: false
    t.string "page_key", limit: 64, null: false
    t.integer "position", null: false
    t.datetime "created_at", null: false
    t.index ["user_id", "page_key"], name: "index_member_pinned_pages_on_user_id_and_page_key", unique: true
  end

  create_table "news_import_removals", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "message_id", limit: 30, null: false
    t.string "removed_by", limit: 30
    t.index ["message_id"], name: "index_news_import_removals_on_message_id", unique: true
  end

  create_table "news_items", force: :cascade do |t|
    t.string "author_id", limit: 30, null: false
    t.string "author_name", limit: 100, null: false
    t.datetime "category_changed_at"
    t.string "category_changed_by", limit: 30
    t.string "category_key", limit: 64
    t.string "channel_id", limit: 30, null: false
    t.text "comment"
    t.datetime "created_at", null: false
    t.datetime "edited_at"
    t.jsonb "images", default: [], null: false
    t.text "link_description"
    t.text "link_image_url"
    t.text "link_site_name"
    t.text "link_title"
    t.text "link_url"
    t.string "message_id", limit: 30, null: false
    t.string "news_copy_message_id", limit: 30
    t.string "news_copy_thread_id", limit: 30
    t.string "origin", limit: 16, default: "live", null: false
    t.string "picked_category_key", limit: 64
    t.datetime "posted_at", null: false
    t.datetime "updated_at", null: false
    t.index ["category_key", "posted_at"], name: "ix_news_items_category_feed", order: { posted_at: :desc }, where: "(category_key IS NOT NULL)"
    t.index ["message_id"], name: "index_news_items_on_message_id", unique: true
    t.index ["posted_at", "id"], name: "ix_news_items_feed", order: :desc, where: "(category_key IS NOT NULL)"
    t.index ["posted_at", "id"], name: "ix_news_items_uncopied", where: "((category_key IS NOT NULL) AND (news_copy_message_id IS NULL))"
    t.check_constraint "(news_copy_message_id IS NULL) = (news_copy_thread_id IS NULL)", name: "ck_news_items_news_copy"
    t.check_constraint "category_key IS NOT NULL OR origin::text = 'import'::text", name: "ck_news_items_category"
    t.check_constraint "origin::text = ANY (ARRAY['live'::character varying, 'import'::character varying]::text[])", name: "ck_news_items_origin"
  end

  create_table "nr_gotm_entries", primary_key: "nr_gotm_id", force: :cascade do |t|
    t.bigint "game_index", null: false
    t.bigint "gamedb_game_id"
    t.string "month_year", limit: 50, null: false
    t.string "reddit_url", limit: 500
    t.bigint "round_number", null: false
    t.string "voting_results_message_id", limit: 50
    t.index ["gamedb_game_id"], name: "idx_nr_gotm_entries_game"
    t.index ["round_number", "game_index"], name: "ux_nr_gotm_entries_rnd_idx", unique: true
  end

  create_table "nr_gotm_nominations", primary_key: "nomination_id", force: :cascade do |t|
    t.bigint "gamedb_game_id", null: false
    t.datetime "nominated_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.string "reason", limit: 1500
    t.bigint "round_number", null: false
    t.string "user_id", limit: 64, null: false
    t.index ["round_number", "user_id"], name: "ux_nr_gotm_noms_round_user", unique: true
    t.index ["round_number"], name: "ix_nr_gotm_noms_round"
  end

  create_table "nr_gotm_votes", primary_key: "vote_id", force: :cascade do |t|
    t.bigint "gamedb_game_id", null: false
    t.bigint "nomination_id", null: false
    t.bigint "round_number", null: false
    t.boolean "runoff", default: false, null: false
    t.string "user_id", limit: 64, null: false
    t.datetime "voted_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.index ["round_number", "nomination_id"], name: "ix_nr_gotm_votes_round_nomination"
    t.index ["round_number", "runoff", "user_id", "gamedb_game_id"], name: "ux_nr_gotm_votes_round_runoff_user_game", unique: true
  end

  create_table "rpg_club_admin_wizard_sessions", primary_key: "session_id", id: { type: :string, limit: 200 }, force: :cascade do |t|
    t.string "channel_id", limit: 64, null: false
    t.string "command_key", limit: 80, null: false
    t.datetime "created_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.string "guild_id", limit: 64
    t.datetime "last_updated_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.string "owner_user_id", limit: 64, null: false
    t.text "state_json", null: false
    t.string "status", limit: 20, default: "active", null: false
    t.datetime "updated_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.index ["command_key", "owner_user_id", "channel_id", "status"], name: "ux_rpg_club_admin_wiz_active", unique: true
    t.index ["command_key", "owner_user_id", "channel_id"], name: "ux_rpg_club_admin_wiz_one_active", unique: true, where: "((status)::text = 'active'::text)"
    t.index ["owner_user_id", "status", "last_updated_at"], name: "ix_rpg_club_admin_wiz_owner_status"
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying::text, 'completed'::character varying::text, 'cancelled'::character varying::text])", name: "ck_rpg_club_admin_wiz_sess_status"
  end

  create_table "rpg_club_collection_csv_import_items", primary_key: "item_id", force: :cascade do |t|
    t.bigint "collection_entry_id"
    t.string "error_text", limit: 2000
    t.bigint "gamedb_game_id"
    t.bigint "import_id", null: false
    t.text "match_candidate_json"
    t.string "match_confidence", limit: 20
    t.string "note", limit: 500
    t.string "ownership_type", limit: 30
    t.bigint "platform_id"
    t.bigint "raw_gamedb_id"
    t.bigint "raw_igdb_id"
    t.string "raw_note", limit: 500
    t.string "raw_ownership_type", limit: 60
    t.string "raw_platform", limit: 200
    t.string "raw_title", limit: 500
    t.string "result_reason", limit: 40
    t.bigint "row_index", null: false
    t.string "status", limit: 20, null: false
    t.index ["import_id", "row_index"], name: "ux_coll_csv_items_import_row", unique: true
    t.index ["import_id", "status", "row_index"], name: "ix_coll_csv_items_import"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'added'::character varying::text, 'updated'::character varying::text, 'skipped'::character varying::text, 'failed'::character varying::text])", name: "ck_coll_csv_items_status"
  end

  create_table "rpg_club_collection_csv_imports", primary_key: "import_id", force: :cascade do |t|
    t.timestamptz "created_at", default: -> { "statement_timestamp()" }, null: false
    t.bigint "current_index", default: 0, null: false
    t.string "source_file_name", limit: 255
    t.bigint "source_file_size"
    t.string "status", limit: 20, null: false
    t.string "template_version", limit: 20
    t.boolean "test_mode", default: false, null: false
    t.bigint "total_count", default: 0, null: false
    t.timestamptz "updated_at", default: -> { "statement_timestamp()" }, null: false
    t.string "user_id", limit: 30, null: false
    t.index ["user_id", "status"], name: "ix_coll_csv_imports_user"
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying::text, 'paused'::character varying::text, 'completed'::character varying::text, 'canceled'::character varying::text])", name: "ck_coll_csv_imports_status"
  end

  create_table "rpg_club_completionator_import_items", primary_key: "item_id", force: :cascade do |t|
    t.datetime "completed_at", precision: 0
    t.bigint "completion_id"
    t.string "completion_type", limit: 50
    t.string "error_text", limit: 2000
    t.string "game_title", limit: 500, null: false
    t.bigint "gamedb_game_id"
    t.bigint "import_id", null: false
    t.string "platform_name", limit: 200
    t.decimal "playtime_hrs"
    t.string "region_name", limit: 200
    t.bigint "row_index", null: false
    t.string "source_type", limit: 100
    t.string "status", limit: 20, null: false
    t.string "time_text", limit: 50
    t.index ["import_id", "status", "row_index"], name: "ix_completionator_items_import"
  end

  create_table "rpg_club_completionator_imports", primary_key: "import_id", force: :cascade do |t|
    t.timestamptz "created_at", default: -> { "statement_timestamp()" }, null: false
    t.bigint "current_index", default: 0, null: false
    t.string "source_filename", limit: 255
    t.string "status", limit: 20, null: false
    t.boolean "test_mode", default: false, null: false
    t.bigint "total_count", default: 0, null: false
    t.timestamptz "updated_at", default: -> { "statement_timestamp()" }, null: false
    t.string "user_id", limit: 30, null: false
    t.index ["user_id", "status"], name: "ix_completionator_imports_user"
  end

  create_table "rpg_club_game_keys", primary_key: "key_id", force: :cascade do |t|
    t.timestamptz "claimed_at"
    t.string "claimed_by_user_id", limit: 30
    t.timestamptz "created_at", default: -> { "statement_timestamp()" }, null: false
    t.boolean "donor_notify_on_claim", default: false, null: false, comment: "1 when the donor requests a notification on claim."
    t.string "donor_user_id", limit: 30, null: false
    t.string "game_title", limit: 200, null: false
    t.bigint "gamedb_game_id"
    t.string "key_value", limit: 200, null: false
    t.string "platform", limit: 50, null: false
    t.string "region", limit: 20, default: "Global", null: false
    t.timestamptz "updated_at", default: -> { "statement_timestamp()" }, null: false
    t.index ["claimed_by_user_id", "game_title"], name: "ix_game_keys_available"
    t.index ["game_title"], name: "ix_game_keys_title"
    t.index ["gamedb_game_id"], name: "ix_game_keys_game"
    t.check_constraint "region::text = ANY (ARRAY['Global'::character varying::text, 'NA'::character varying::text, 'EU'::character varying::text, 'UK'::character varying::text, 'RU/CIS'::character varying::text, 'Asia'::character varying::text, 'Unknown'::character varying::text])", name: "ck_rpg_club_game_keys_region"
  end

  create_table "rpg_club_gamedb_import_items", primary_key: "item_id", force: :cascade do |t|
    t.string "error_text", limit: 2000
    t.string "game_title", limit: 500, null: false
    t.bigint "gamedb_game_id"
    t.bigint "import_id", null: false
    t.datetime "initial_release_date", precision: 0
    t.string "platform_name", limit: 200
    t.string "raw_game_title", limit: 500
    t.string "region_name", limit: 200
    t.bigint "row_index", null: false
    t.string "status", limit: 20, null: false
    t.index ["import_id", "status", "row_index"], name: "ix_gamedb_items_import"
  end

  create_table "rpg_club_gamedb_import_title_map", primary_key: "map_id", force: :cascade do |t|
    t.timestamptz "created_at", default: -> { "statement_timestamp()" }, null: false
    t.string "created_by", limit: 30
    t.bigint "gamedb_game_id"
    t.string "status", limit: 20, null: false
    t.string "title_norm", limit: 500, null: false
    t.string "title_raw", limit: 500, null: false
    t.timestamptz "updated_at", default: -> { "statement_timestamp()" }, null: false
    t.index ["status"], name: "ix_gamedb_import_title_status"
    t.index ["title_norm"], name: "ux_gamedb_import_title_norm", unique: true
  end

  create_table "rpg_club_gamedb_imports", primary_key: "import_id", force: :cascade do |t|
    t.timestamptz "created_at", default: -> { "statement_timestamp()" }, null: false
    t.bigint "current_index", default: 0, null: false
    t.string "source_filename", limit: 255
    t.string "status", limit: 20, null: false
    t.bigint "total_count", default: 0, null: false
    t.timestamptz "updated_at", default: -> { "statement_timestamp()" }, null: false
    t.string "user_id", limit: 30, null: false
    t.index ["user_id", "status"], name: "ix_gamedb_imports_user"
  end

  create_table "rpg_club_gotm_audit_imports", primary_key: "import_id", force: :cascade do |t|
    t.timestamptz "created_at", default: -> { "statement_timestamp()" }, null: false
    t.bigint "current_index", default: 0, null: false
    t.string "source_filename", limit: 255
    t.string "status", limit: 20, null: false
    t.bigint "total_count", default: 0, null: false
    t.timestamptz "updated_at", default: -> { "statement_timestamp()" }, null: false
    t.string "user_id", limit: 30, null: false
    t.index ["user_id", "status"], name: "ix_gotm_audit_imports_user"
  end

  create_table "rpg_club_gotm_audit_items", primary_key: "item_id", force: :cascade do |t|
    t.string "error_text", limit: 2000
    t.bigint "game_index", null: false
    t.string "game_title", limit: 500, null: false
    t.bigint "gamedb_game_id"
    t.bigint "import_id", null: false
    t.string "kind", limit: 10, null: false
    t.string "month_year", limit: 50, null: false
    t.string "reddit_url", limit: 1000
    t.bigint "round_number", null: false
    t.bigint "row_index", null: false
    t.string "status", limit: 20, null: false
    t.string "thread_id", limit: 30
    t.index ["import_id", "kind", "round_number"], name: "ix_gotm_audit_items_round"
    t.index ["import_id", "status", "row_index"], name: "ix_gotm_audit_items_import"
  end

  create_table "rpg_club_hltb_cache", primary_key: "cache_id", force: :cascade do |t|
    t.string "co_op", limit: 50
    t.string "completionist", limit: 50
    t.bigint "gamedb_game_id", null: false
    t.string "hltb_image_url", limit: 512
    t.string "hltb_name", limit: 255
    t.string "hltb_url", limit: 512
    t.string "main", limit: 50
    t.string "main_sides", limit: 50
    t.datetime "scraped_at", default: -> { "CURRENT_TIMESTAMP" }
    t.datetime "searched_at"
    t.string "single_player", limit: 50
    t.string "source_query", limit: 255
    t.datetime "updated_at", default: -> { "CURRENT_TIMESTAMP" }
    t.string "vs", limit: 50
    t.index ["gamedb_game_id"], name: "uq_hltb_game_id", unique: true
  end

  create_table "rpg_club_presence_prompt_history", primary_key: "prompt_id", id: { type: :string, limit: 64 }, force: :cascade do |t|
    t.timestamptz "created_at", default: -> { "statement_timestamp()" }, null: false
    t.string "game_title", limit: 300, null: false
    t.string "game_title_norm", limit: 300, null: false
    t.timestamptz "resolved_at"
    t.string "status", limit: 20, default: "PENDING", null: false
    t.string "user_id", limit: 30, null: false
    t.index ["user_id", "game_title_norm", "status"], name: "idx_rpg_club_presence_prompt_hist_user"
  end

  create_table "rpg_club_presence_prompt_opts", primary_key: ["user_id", "scope", "game_title_norm"], force: :cascade do |t|
    t.timestamptz "created_at", default: -> { "statement_timestamp()" }, null: false
    t.string "game_title", limit: 300
    t.string "game_title_norm", limit: 300, null: false
    t.string "scope", limit: 10, null: false
    t.string "user_id", limit: 30, null: false
    t.check_constraint "scope::text = ANY (ARRAY['ALL'::character varying::text, 'GAME'::character varying::text])", name: "ck_rpg_club_presence_prompt_scope"
  end

  create_table "rpg_club_public_reminders", primary_key: "reminder_id", force: :cascade do |t|
    t.string "channel_id", limit: 30, null: false
    t.timestamptz "created_at", default: -> { "statement_timestamp()" }, null: false
    t.string "created_by", limit: 30
    t.timestamptz "due_at", null: false
    t.boolean "enabled", default: true, null: false
    t.string "message", limit: 2000, null: false
    t.bigint "recur_every"
    t.string "recur_unit", limit: 10
    t.timestamptz "updated_at", default: -> { "statement_timestamp()" }, null: false
    t.index ["due_at", "enabled"], name: "ix_rpg_club_public_reminders_due"
  end

  create_table "rpg_club_raw_modal_sessions", primary_key: "session_id", id: { type: :string, limit: 120 }, force: :cascade do |t|
    t.string "channel_id", limit: 30
    t.timestamptz "created_at", default: -> { "statement_timestamp()" }, null: false
    t.timestamptz "expires_at", null: false
    t.string "feature_id", limit: 60, null: false
    t.string "flow_id", limit: 60, null: false
    t.string "guild_id", limit: 30
    t.string "owner_user_id", limit: 30, null: false
    t.text "state_json", null: false
    t.string "status", limit: 20, default: "OPEN", null: false
    t.timestamptz "updated_at", default: -> { "statement_timestamp()" }, null: false
    t.index ["expires_at"], name: "ix_raw_modal_sess_expires"
    t.index ["owner_user_id", "status"], name: "ix_raw_modal_sess_owner_status"
    t.check_constraint "status::text = ANY (ARRAY['OPEN'::character varying::text, 'SUBMITTED'::character varying::text, 'EXPIRED'::character varying::text])", name: "ck_raw_modal_session_status"
  end

  create_table "rpg_club_rss_feed_items", primary_key: ["feed_id", "item_id_hash"], force: :cascade do |t|
    t.timestamptz "created_at", default: -> { "statement_timestamp()" }, null: false
    t.bigint "feed_id", null: false
    t.string "item_id_hash", limit: 128, null: false
    t.timestamptz "published_at"
    t.string "title"
    t.string "url", limit: 2048
  end

  create_table "rpg_club_rss_feeds", primary_key: "feed_id", force: :cascade do |t|
    t.string "channel_id", limit: 30, null: false
    t.timestamptz "created_at", default: -> { "statement_timestamp()" }, null: false
    t.string "exclude_keywords", limit: 4000
    t.string "feed_name", limit: 200
    t.string "feed_url", limit: 512, null: false
    t.string "include_keywords", limit: 4000
    t.timestamptz "updated_at", default: -> { "statement_timestamp()" }, null: false
    t.index ["channel_id", "feed_url"], name: "ux_rpg_club_rss_feeds_channel_url", unique: true
  end

  create_table "rpg_club_starboard", primary_key: "message_id", id: { type: :string, limit: 30 }, force: :cascade do |t|
    t.string "author_id", limit: 30, null: false
    t.string "channel_id", limit: 30, null: false
    t.timestamptz "created_at", default: -> { "statement_timestamp()" }, null: false
    t.integer "star_count", default: 0, null: false
    t.string "starboard_message_id", limit: 30, null: false
  end

  create_table "rpg_club_steam_app_gamedb_map", primary_key: "map_id", force: :cascade do |t|
    t.timestamptz "created_at", default: -> { "statement_timestamp()" }, null: false
    t.string "created_by", limit: 30
    t.bigint "gamedb_game_id"
    t.string "status", limit: 20, null: false
    t.bigint "steam_app_id", null: false
    t.timestamptz "updated_at", default: -> { "statement_timestamp()" }, null: false
    t.index ["created_by", "status"], name: "ix_steam_app_gamedb_map_creator"
    t.index ["status"], name: "ix_steam_app_gamedb_map_status"
    t.check_constraint "status::text = ANY (ARRAY['mapped'::character varying::text, 'skipped'::character varying::text])", name: "ck_steam_app_gamedb_map_status"
    t.unique_constraint ["steam_app_id"], name: "rpg_club_steam_app_gamedb_map_steam_app_id_key"
  end

  create_table "rpg_club_steam_collection_import_items", primary_key: "item_id", force: :cascade do |t|
    t.bigint "collection_entry_id"
    t.string "error_text", limit: 2000
    t.bigint "gamedb_game_id"
    t.bigint "import_id", null: false
    t.datetime "last_played_at", precision: 0
    t.text "match_candidate_json"
    t.string "match_confidence", limit: 20
    t.bigint "playtime_deck_min"
    t.bigint "playtime_forever_min"
    t.bigint "playtime_linux_min"
    t.bigint "playtime_mac_min"
    t.bigint "playtime_windows_min"
    t.string "result_reason", limit: 40
    t.bigint "row_index", null: false
    t.string "status", limit: 20, null: false
    t.bigint "steam_app_id", null: false
    t.string "steam_app_name", limit: 500, null: false
    t.index ["import_id", "row_index"], name: "ux_steam_coll_items_import_row", unique: true
    t.index ["import_id", "status", "row_index"], name: "ix_steam_coll_items_import"
    t.index ["steam_app_id"], name: "ix_steam_coll_items_app"
    t.check_constraint "match_confidence IS NULL OR (match_confidence::text = ANY (ARRAY['exact'::character varying::text, 'fuzzy'::character varying::text, 'manual'::character varying::text]))", name: "ck_steam_coll_items_match_confidence"
    t.check_constraint "result_reason IS NULL OR (result_reason::text = ANY (ARRAY['auto_match'::character varying::text, 'manual_remap'::character varying::text, 'duplicate'::character varying::text, 'manual_skip'::character varying::text, 'skip_mapped'::character varying::text, 'no_candidate'::character varying::text, 'invalid_remap'::character varying::text, 'platform_unresolved'::character varying::text, 'add_failed'::character varying::text]))", name: "ck_steam_coll_items_reason"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'added'::character varying::text, 'updated'::character varying::text, 'skipped'::character varying::text, 'failed'::character varying::text])", name: "ck_steam_coll_items_status"
  end

  create_table "rpg_club_steam_collection_imports", primary_key: "import_id", force: :cascade do |t|
    t.timestamptz "created_at", default: -> { "statement_timestamp()" }, null: false
    t.bigint "current_index", default: 0, null: false
    t.string "source_profile_name", limit: 255
    t.string "status", limit: 20, null: false
    t.string "steam_id64", limit: 20, null: false
    t.string "steam_profile_ref", limit: 255
    t.boolean "test_mode", default: false, null: false
    t.bigint "total_count", default: 0, null: false
    t.timestamptz "updated_at", default: -> { "statement_timestamp()" }, null: false
    t.string "user_id", limit: 30, null: false
    t.index ["user_id", "status"], name: "ix_steam_coll_imports_user"
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying::text, 'paused'::character varying::text, 'completed'::character varying::text, 'canceled'::character varying::text])", name: "ck_steam_coll_imports_status"
  end

  create_table "rpg_club_suggestion_review_sessions", primary_key: "session_id", id: { type: :string, limit: 120 }, force: :cascade do |t|
    t.timestamptz "created_at", default: -> { "statement_timestamp()" }, null: false
    t.bigint "current_index", default: 0, null: false
    t.string "reviewer_id", limit: 30, null: false
    t.string "suggestion_ids", limit: 4000, null: false
    t.bigint "total_count", default: 0, null: false
    t.timestamptz "updated_at", default: -> { "statement_timestamp()" }, null: false
    t.index ["created_at"], name: "ix_rpg_club_sug_rev_sess_created"
    t.index ["reviewer_id"], name: "ix_rpg_club_sug_rev_sess_reviewer"
  end

  create_table "rpg_club_suggestion_upvotes", force: :cascade do |t|
    t.timestamptz "created_at", default: -> { "statement_timestamp()" }, null: false
    t.bigint "suggestion_id", null: false
    t.string "user_id", limit: 30, null: false
    t.index ["suggestion_id", "user_id"], name: "ux_rpg_club_suggestion_upvotes_suggestion_user", unique: true
    t.index ["user_id"], name: "ix_rpg_club_suggestion_upvotes_user"
  end

  create_table "rpg_club_suggestions", primary_key: "suggestion_id", force: :cascade do |t|
    t.timestamptz "approval_started_at"
    t.timestamptz "created_at", default: -> { "statement_timestamp()" }, null: false
    t.string "created_by", limit: 30
    t.string "created_by_name", limit: 100
    t.string "details", limit: 2000
    t.integer "github_issue_number"
    t.string "github_issue_url", limit: 500
    t.string "labels", limit: 200
    t.string "rejection_reason", limit: 2000
    t.timestamptz "reviewed_at"
    t.string "reviewed_by", limit: 30
    t.string "status", limit: 16, default: "pending", null: false
    t.string "target_repo", limit: 200
    t.string "title", limit: 200, null: false
    t.timestamptz "updated_at", default: -> { "statement_timestamp()" }, null: false
    t.index ["created_at"], name: "ix_rpg_club_suggestions_created"
    t.index ["status"], name: "ix_rpg_club_suggestions_status"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying, 'approved'::character varying, 'rejected'::character varying, 'withdrawn'::character varying]::text[])", name: "ck_rpg_club_suggestions_status"
  end

  create_table "rpg_club_user_avatar_history", primary_key: "event_id", force: :cascade do |t|
    t.binary "avatar_blob"
    t.string "avatar_hash", limit: 128
    t.string "avatar_url", limit: 512
    t.timestamptz "changed_at", default: -> { "statement_timestamp()" }, null: false
    t.string "user_id", limit: 30, null: false
    t.index ["user_id", "changed_at"], name: "ix_rpg_club_user_avatar_history_user"
  end

  create_table "rpg_club_user_nick_history", primary_key: "event_id", force: :cascade do |t|
    t.timestamptz "changed_at", default: -> { "statement_timestamp()" }, null: false
    t.string "new_nick", limit: 100
    t.string "old_nick", limit: 100
    t.string "user_id", limit: 30, null: false
    t.index ["user_id", "changed_at"], name: "ix_rpg_club_user_nick_history_user"
  end

  create_table "rpg_club_users", primary_key: "user_id", id: { type: :string, limit: 30 }, force: :cascade do |t|
    t.binary "avatar_blob"
    t.timestamptz "created_at", default: -> { "statement_timestamp()" }, null: false
    t.string "discord_avatar", limit: 128
    t.boolean "donor_notify_on_claim", default: false, null: false, comment: "1 when the user wants to be notified when a donated key is claimed."
    t.string "emoji_name", limit: 32
    t.string "global_name", limit: 100
    t.boolean "is_bot", default: false, null: false
    t.timestamptz "last_fetched_at"
    t.timestamptz "last_seen_at"
    t.bigint "message_count", default: 0
    t.binary "profile_image"
    t.timestamptz "profile_image_at"
    t.boolean "role_admin", default: false, null: false
    t.boolean "role_member", default: false, null: false
    t.boolean "role_moderator", default: false, null: false
    t.boolean "role_newcomer", default: false, null: false
    t.boolean "role_regular", default: false, null: false
    t.timestamptz "server_joined_at"
    t.timestamptz "server_left_at"
    t.timestamptz "updated_at", default: -> { "statement_timestamp()" }, null: false
    t.string "username", limit: 100
    t.boolean "role_dev", default: false, null: false
    t.boolean "show_preview_features", default: true, null: false, comment: "Staff setting: show Preview Features on the website (on by default)."
    t.boolean "challenge_dms", default: true, null: false, comment: "Whether the member wants Challenge reminder DMs (on by default)."
    t.integer "birth_month", limit: 2, comment: "The member's Birth Date: its month, 1 to 12."
    t.integer "birth_day", limit: 2, comment: "The member's Birth Date: its day of the month (29 February allowed without a year)."
    t.integer "birth_year", limit: 2, comment: "The member's Birth Date: its year, or null when the member gave only the day and month."
    t.boolean "birthday_shared", default: false, null: false, comment: "Whether the member shares their Birthday (the day and month of their Birth Date, never the year). Only the member turns it on; staff can turn it off; removing the Birth Date turns it off."
    t.boolean "pinned_pages_customised", default: false, null: false, comment: "Whether the member saved their own Pinned Pages; false follows the club default."
    t.boolean "dashboard_panels_customised", default: false, null: false, comment: "Whether the member saved their own Dashboard Panels; false follows the club default."
    t.string "dashboard_panels_seen_keys", comment: "Dashboard Panel keys the member has seen in edit mode; NULL until they first open it.", array: true
    t.check_constraint "birth_month IS NULL AND birth_day IS NULL AND birth_year IS NULL OR birth_month IS NOT NULL AND birth_day IS NOT NULL AND birth_month >= 1 AND birth_month <= 12 AND birth_day >= 1 AND birth_day <=\nCASE\n    WHEN birth_month = 2 THEN 29\n    WHEN birth_month = ANY (ARRAY[4, 6, 9, 11]) THEN 30\n    ELSE 31\nEND", name: "ck_rpg_club_users_birth_date"
    t.check_constraint "NOT birthday_shared OR birth_month IS NOT NULL", name: "ck_rpg_club_users_birthday_shared"
  end

  create_table "rpg_club_users_hist", primary_key: "history_id", force: :cascade do |t|
    t.string "action_type", limit: 1, null: false
    t.timestamptz "actioned_at", default: -> { "statement_timestamp()" }, null: false
    t.binary "avatar_blob"
    t.string "completionator_url", limit: 512
    t.timestamptz "created_at"
    t.boolean "donor_notify_on_claim", comment: "Audit snapshot of donor notification preference."
    t.string "global_name", limit: 100
    t.boolean "is_bot"
    t.timestamptz "last_fetched_at"
    t.timestamptz "last_seen_at"
    t.bigint "message_count"
    t.string "nsw_friend_code", limit: 50
    t.binary "profile_image"
    t.timestamptz "profile_image_at"
    t.string "psn_username", limit: 100
    t.boolean "role_admin"
    t.boolean "role_member"
    t.boolean "role_moderator"
    t.boolean "role_newcomer"
    t.boolean "role_regular"
    t.timestamptz "server_joined_at"
    t.timestamptz "server_left_at"
    t.string "steam_url", limit: 512
    t.timestamptz "updated_at"
    t.string "user_id", limit: 30, null: false
    t.string "username", limit: 100
    t.string "xbl_username", limit: 100
    t.index ["user_id"], name: "idx_rpg_club_users_hist_user"
  end

  create_table "rpg_club_xbox_collection_import_items", primary_key: "item_id", force: :cascade do |t|
    t.bigint "collection_entry_id"
    t.string "error_text", limit: 2000
    t.bigint "gamedb_game_id"
    t.bigint "import_id", null: false
    t.text "match_candidate_json"
    t.string "match_confidence", limit: 20
    t.string "note", limit: 500
    t.string "ownership_type", limit: 30
    t.bigint "platform_id"
    t.bigint "raw_gamedb_id"
    t.bigint "raw_igdb_id"
    t.string "raw_note", limit: 500
    t.string "raw_ownership_type", limit: 60
    t.string "raw_platform", limit: 200
    t.string "result_reason", limit: 40
    t.bigint "row_index", null: false
    t.string "status", limit: 20, null: false
    t.string "xbox_product_id", limit: 80
    t.string "xbox_title_id", limit: 40
    t.string "xbox_title_name", limit: 500, null: false
    t.index ["import_id", "status", "row_index"], name: "ix_xbox_coll_items_import"
    t.index ["xbox_title_id"], name: "ix_xbox_coll_items_title"
    t.check_constraint "result_reason IS NULL OR (result_reason::text = ANY (ARRAY['AUTO_MATCH'::character varying::text, 'XBOX_GAMEDB_ID'::character varying::text, 'XBOX_IGDB_ID'::character varying::text, 'MANUAL_REMAP'::character varying::text, 'DUPLICATE'::character varying::text, 'MANUAL_SKIP'::character varying::text, 'SKIP_MAPPED'::character varying::text, 'NO_CANDIDATE'::character varying::text, 'INVALID_REMAP'::character varying::text, 'PLATFORM_UNRESOLVED'::character varying::text, 'ADD_FAILED'::character varying::text, 'INVALID_ROW'::character varying::text]))", name: "ck_xbox_coll_items_reason"
    t.check_constraint "status::text = ANY (ARRAY['PENDING'::character varying::text, 'ADDED'::character varying::text, 'UPDATED'::character varying::text, 'SKIPPED'::character varying::text, 'FAILED'::character varying::text])", name: "ck_xbox_coll_items_status"
  end

  create_table "rpg_club_xbox_collection_imports", primary_key: "import_id", force: :cascade do |t|
    t.timestamptz "created_at", default: -> { "statement_timestamp()" }, null: false
    t.bigint "current_index", default: 0, null: false
    t.string "gamertag", limit: 100
    t.string "source_file_name", limit: 255
    t.bigint "source_file_size"
    t.string "source_type", limit: 20, null: false
    t.string "status", limit: 20, null: false
    t.string "template_version", limit: 20
    t.bigint "total_count", default: 0, null: false
    t.timestamptz "updated_at", default: -> { "statement_timestamp()" }, null: false
    t.string "user_id", limit: 30, null: false
    t.string "xuid", limit: 30
    t.index ["user_id", "status"], name: "ix_xbox_coll_imports_user"
    t.check_constraint "source_type::text = ANY (ARRAY['API'::character varying::text, 'CSV'::character varying::text])", name: "ck_xbox_coll_imports_source"
    t.check_constraint "status::text = ANY (ARRAY['ACTIVE'::character varying::text, 'PAUSED'::character varying::text, 'COMPLETED'::character varying::text, 'CANCELED'::character varying::text])", name: "ck_xbox_coll_imports_status"
  end

  create_table "rpg_club_xbox_title_gamedb_map", primary_key: "map_id", force: :cascade do |t|
    t.timestamptz "created_at", default: -> { "statement_timestamp()" }, null: false
    t.string "created_by", limit: 30
    t.bigint "gamedb_game_id"
    t.string "status", limit: 20, null: false
    t.timestamptz "updated_at", default: -> { "statement_timestamp()" }, null: false
    t.string "xbox_title_id", limit: 40, null: false
    t.index ["status"], name: "ix_xbox_title_gamedb_map_status"
    t.index ["xbox_title_id"], name: "ux_xbox_title_gamedb_map_title", unique: true
    t.check_constraint "status::text = ANY (ARRAY['MAPPED'::character varying::text, 'SKIPPED'::character varying::text])", name: "ck_xbox_title_gamedb_map_status"
  end

  create_table "social_platforms", force: :cascade do |t|
    t.datetime "created_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.string "created_by_user_id", limit: 30
    t.string "label", limit: 80, null: false
    t.integer "position", default: 1000, null: false
    t.datetime "updated_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.index "lower((label)::text)", name: "index_social_platforms_on_lower_label", unique: true
    t.index ["position"], name: "index_social_platforms_on_position"
  end

  create_table "thread_game_links", primary_key: ["thread_id", "gamedb_game_id"], force: :cascade do |t|
    t.bigint "gamedb_game_id", null: false
    t.timestamptz "linked_at", default: -> { "statement_timestamp()" }, null: false
    t.string "thread_id", limit: 50, null: false
    t.index ["gamedb_game_id"], name: "ix_thread_game_links_game"
  end

  create_table "threads", primary_key: "thread_id", id: { type: :string, limit: 30 }, force: :cascade do |t|
    t.timestamptz "created_at", default: -> { "statement_timestamp()" }, null: false
    t.string "forum_channel_id", limit: 30, null: false
    t.bigint "gamedb_game_id"
    t.string "is_archived", limit: 1, default: "N", null: false
    t.timestamptz "last_seen_at"
    t.string "skip_linking", limit: 1, default: "N", null: false
    t.string "thread_name", limit: 200, null: false
    t.index ["forum_channel_id"], name: "ix_threads_forum"
    t.index ["gamedb_game_id"], name: "ix_threads_gamedb"
    t.check_constraint "is_archived::text = ANY (ARRAY['Y'::character varying::text, 'N'::character varying::text])", name: "ck_threads_is_archived"
    t.check_constraint "skip_linking::text = ANY (ARRAY['Y'::character varying::text, 'N'::character varying::text])", name: "ck_threads_skip_linking"
  end

  create_table "user_achievement_set_progress", force: :cascade do |t|
    t.bigint "achievement_set_id", null: false
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.integer "earned_count", default: 0, null: false
    t.integer "hardcore_earned_count", default: 0, null: false
    t.datetime "last_unlocked_at"
    t.datetime "mastered_at"
    t.datetime "platinum_at"
    t.integer "playtime_minutes"
    t.integer "points_earned", default: 0, null: false
    t.datetime "sync_pending_at"
    t.datetime "synced_at"
    t.integer "total_count", default: 0, null: false
    t.datetime "updated_at", null: false
    t.string "user_id", limit: 30, null: false
    t.bigint "user_linked_account_id", null: false
    t.index ["achievement_set_id"], name: "ix_user_achievement_set_progress_set"
    t.index ["sync_pending_at"], name: "ix_user_achievement_set_progress_sync_pending", where: "(sync_pending_at IS NOT NULL)"
    t.index ["user_id", "achievement_set_id"], name: "ux_user_achievement_set_progress_user_set", unique: true
    t.index ["user_id", "last_unlocked_at"], name: "ix_user_achievement_set_progress_user_last_unlocked"
    t.index ["user_linked_account_id"], name: "ix_user_achievement_set_progress_linked_account"
  end

  create_table "user_achievement_unlocks", force: :cascade do |t|
    t.bigint "achievement_id", null: false
    t.boolean "announceable", default: false, null: false
    t.datetime "announced_at"
    t.datetime "created_at", null: false
    t.boolean "hardcore", default: false, null: false
    t.datetime "hardcore_unlocked_at"
    t.string "highlight", limit: 16
    t.datetime "unlocked_at", null: false
    t.datetime "updated_at", null: false
    t.string "user_id", limit: 30, null: false
    t.bigint "user_linked_account_id", null: false
    t.index ["achievement_id"], name: "ix_user_achievement_unlocks_achievement"
    t.index ["id"], name: "ix_user_achievement_unlocks_unannounced", where: "(announceable AND (announced_at IS NULL))"
    t.index ["unlocked_at"], name: "ix_user_achievement_unlocks_unlocked_at"
    t.index ["user_id", "achievement_id"], name: "ux_user_achievement_unlocks_user_achievement", unique: true
    t.index ["user_id", "unlocked_at", "id"], name: "ix_user_achievement_unlocks_user_unlocked_at", order: { unlocked_at: :desc, id: :desc }
    t.index ["user_linked_account_id"], name: "ix_user_achievement_unlocks_linked_account"
  end

  create_table "user_franchise_conquests", force: :cascade do |t|
    t.string "user_id", limit: 30, null: false
    t.bigint "franchise_id", null: false
    t.datetime "conquered_at", null: false
    t.bigint "completion_id"
    t.boolean "announce", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["franchise_id"], name: "index_user_franchise_conquests_on_franchise_id"
    t.index ["user_id", "franchise_id"], name: "ux_user_franchise_conquests_member", unique: true
  end

  create_table "user_game_backlog", primary_key: "entry_id", force: :cascade do |t|
    t.datetime "created_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.bigint "gamedb_game_id", null: false
    t.string "note", limit: 500
    t.bigint "platform_id"
    t.bigint "sort_order"
    t.datetime "updated_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.string "user_id", limit: 50, null: false
    t.index ["platform_id"], name: "ix_user_game_backlog_platform"
    t.index ["user_id", "gamedb_game_id", "platform_id"], name: "uq_user_game_backlog_user_game_platform", unique: true
    t.index ["user_id", "sort_order"], name: "ix_user_game_backlog_sort"
    t.index ["user_id"], name: "ix_user_game_backlog_user"
  end

  create_table "user_game_collections", primary_key: "entry_id", force: :cascade do |t|
    t.datetime "created_at", default: -> { "statement_timestamp()" }, null: false
    t.bigint "gamedb_game_id", null: false
    t.boolean "is_shared", default: true, null: false
    t.string "note", limit: 500
    t.string "ownership_type", limit: 30, default: "Digital", null: false
    t.bigint "platform_id"
    t.datetime "updated_at", default: -> { "statement_timestamp()" }, null: false
    t.string "user_id", limit: 50, null: false
    t.index "user_id, gamedb_game_id, COALESCE(platform_id, ('-1'::integer)::bigint), ownership_type", name: "uq_user_game_collections_dedup", unique: true
    t.index ["gamedb_game_id"], name: "ix_ugcol_game"
    t.index ["platform_id"], name: "ix_ugcol_platform"
    t.index ["user_id", "is_shared"], name: "ix_ugcol_shared"
    t.index ["user_id"], name: "ix_ugcol_user"
    t.check_constraint "ownership_type::text = ANY (ARRAY['Digital'::character varying::text, 'Physical'::character varying::text, 'Subscription'::character varying::text, 'Other'::character varying::text])", name: "ck_ugcol_ownership_type"
  end

  create_table "user_game_completions", primary_key: "completion_id", force: :cascade do |t|
    t.datetime "completed_at", precision: 0, default: -> { "date_trunc('day'::text, statement_timestamp())" }
    t.string "completion_type", limit: 50, null: false
    t.datetime "created_at", default: -> { "statement_timestamp()" }, null: false
    t.decimal "final_playtime_hrs", precision: 8, scale: 2
    t.bigint "gamedb_game_id", null: false
    t.string "note", limit: 500
    t.bigint "platform_id"
    t.string "user_id", limit: 50, null: false
    t.date "started_at"
    t.index ["completed_at", "created_at", "completion_id"], name: "ix_ugc_recent", order: { completed_at: "DESC NULLS LAST", created_at: :desc, completion_id: :desc }
    t.index ["gamedb_game_id"], name: "ix_ugc_game"
    t.index ["platform_id"], name: "idx_user_game_completions_platform"
    t.index ["user_id"], name: "ix_ugc_user"
    t.index ["user_id", "completed_at", "created_at"], name: "ix_ugc_user_completed_at", order: { completed_at: :desc, created_at: :desc }
    t.check_constraint "completion_type::text = ANY (ARRAY['Main Story'::character varying::text, 'Main Story + Side Content'::character varying::text, 'Completionist'::character varying::text])", name: "ck_user_game_completions_type"
  end

  create_table "user_game_favorites", primary_key: "entry_id", force: :cascade do |t|
    t.datetime "created_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.bigint "gamedb_game_id", null: false
    t.string "note", limit: 500
    t.bigint "sort_order"
    t.datetime "updated_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.string "user_id", limit: 50, null: false
    t.index ["gamedb_game_id"], name: "ix_user_game_favorites_game"
    t.index ["user_id", "gamedb_game_id"], name: "uq_user_game_favorites_user_game", unique: true
    t.index ["user_id", "sort_order"], name: "ix_user_game_favorites_sort"
  end

  create_table "user_game_journal_entries", primary_key: "entry_id", force: :cascade do |t|
    t.datetime "created_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.text "entry_body", null: false
    t.string "entry_title", limit: 120
    t.bigint "gamedb_game_id", null: false
    t.datetime "updated_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.string "user_id", limit: 50, null: false
    t.index ["gamedb_game_id"], name: "ix_user_game_journal_entries_game"
    t.index ["user_id", "gamedb_game_id"], name: "ix_user_game_journal_entries_user_game"
    t.index ["user_id"], name: "ix_user_game_journal_entries_user"
  end

  create_table "user_game_manual_playtimes", force: :cascade do |t|
    t.string "user_id", limit: 30, null: false
    t.bigint "gamedb_game_id", null: false
    t.bigint "platform_id"
    t.integer "minutes", default: 0, null: false
    t.string "note", limit: 280
    t.string "origin", limit: 32, default: "member", null: false
    t.string "keeps_over_provider", limit: 32
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "mismatch_acknowledged_provider", limit: 32
    t.index ["gamedb_game_id"], name: "index_user_game_manual_playtimes_on_gamedb_game_id"
    t.index ["user_id", "gamedb_game_id", "platform_id"], name: "ux_user_game_manual_playtimes_platform", unique: true, nulls_not_distinct: true
    t.check_constraint "minutes >= 0", name: "ck_user_game_manual_playtimes_minutes"
    t.check_constraint "origin::text = ANY (ARRAY['member'::character varying, 'completion_seed'::character varying]::text[])", name: "ck_user_game_manual_playtimes_origin"
  end

  create_table "user_game_playthroughs", force: :cascade do |t|
    t.string "user_id", limit: 30, null: false
    t.bigint "gamedb_game_id", null: false
    t.datetime "started_at", null: false
    t.integer "baseline_minutes", default: 0, null: false
    t.integer "manual_total_minutes"
    t.datetime "ended_at"
    t.string "end_reason", limit: 16
    t.bigint "completion_id"
    t.integer "final_minutes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["completion_id"], name: "index_user_game_playthroughs_on_completion_id"
    t.index ["gamedb_game_id"], name: "index_user_game_playthroughs_on_gamedb_game_id"
    t.index ["user_id", "gamedb_game_id"], name: "ux_user_game_playthroughs_open", unique: true, where: "(ended_at IS NULL)"
    t.check_constraint "(ended_at IS NULL) = (end_reason IS NULL)", name: "ck_user_game_playthroughs_ended"
    t.check_constraint "baseline_minutes >= 0 AND manual_total_minutes >= 0 AND final_minutes >= 0", name: "ck_user_game_playthroughs_minutes"
    t.check_constraint "end_reason::text = ANY (ARRAY['completed'::character varying, 'abandoned'::character varying]::text[])", name: "ck_user_game_playthroughs_end_reason"
  end

  create_table "user_game_review_revisions", primary_key: "revision_id", force: :cascade do |t|
    t.bigint "review_id", null: false
    t.integer "rating"
    t.string "title", limit: 120
    t.jsonb "body"
    t.jsonb "facets"
    t.datetime "published_at"
    t.datetime "edited_at"
    t.datetime "created_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.datetime "updated_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.index ["review_id", "published_at"], name: "ix_user_game_review_revisions_review"
    t.index ["review_id"], name: "uq_user_game_review_revisions_one_draft", unique: true, where: "(published_at IS NULL)"
    t.check_constraint "published_at IS NULL OR rating IS NOT NULL", name: "ck_user_game_review_revisions_rating_when_published"
    t.check_constraint "rating >= 0 AND rating <= 100", name: "ck_user_game_review_revisions_rating_range"
  end

  create_table "user_game_reviews", primary_key: "review_id", force: :cascade do |t|
    t.jsonb "body"
    t.datetime "created_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.jsonb "facets"
    t.bigint "gamedb_game_id", null: false
    t.integer "rating"
    t.string "title", limit: 120
    t.datetime "updated_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.string "user_id", limit: 50, null: false
    t.datetime "published_at"
    t.datetime "edited_at"
    t.index ["gamedb_game_id"], name: "ix_user_game_reviews_game"
    t.index ["user_id", "gamedb_game_id"], name: "uq_user_game_reviews_user_game", unique: true
    t.index ["user_id"], name: "ix_user_game_reviews_user"
    t.check_constraint "published_at IS NULL OR rating IS NOT NULL", name: "ck_user_game_reviews_rating_when_published"
    t.check_constraint "rating >= 0 AND rating <= 100", name: "ck_user_game_reviews_rating_range"
  end

  create_table "user_linked_accounts", force: :cascade do |t|
    t.datetime "backfilled_at"
    t.datetime "created_at", null: false
    t.string "display_name", limit: 255
    t.string "external_id", limit: 64, null: false
    t.datetime "last_synced_at"
    t.string "provider", limit: 32, null: false
    t.datetime "sync_due_at"
    t.text "sync_error"
    t.string "sync_mode", limit: 32, default: "backfill", null: false
    t.datetime "sync_requested_at"
    t.string "sync_status", limit: 32, default: "pending", null: false
    t.datetime "updated_at", null: false
    t.string "user_id", limit: 30, null: false
    t.index ["provider", "external_id"], name: "ux_user_linked_accounts_provider_external", unique: true
    t.index ["provider", "sync_due_at"], name: "ix_user_linked_accounts_sync_due", where: "(sync_due_at IS NOT NULL)"
    t.index ["user_id", "provider"], name: "ux_user_linked_accounts_user_provider", unique: true
  end

  create_table "user_now_playing", primary_key: "entry_id", force: :cascade do |t|
    t.timestamptz "added_at", default: -> { "statement_timestamp()" }, null: false
    t.bigint "gamedb_game_id"
    t.string "note", limit: 500
    t.timestamptz "note_updated_at"
    t.bigint "platform_id"
    t.bigint "sort_order"
    t.string "user_id", limit: 30, null: false
    t.index ["platform_id"], name: "ix_user_now_playing_platform"
    t.index ["user_id", "gamedb_game_id"], name: "uq_user_now_playing_gamedb", unique: true
    t.index ["user_id", "sort_order"], name: "ix_user_now_playing_sort"
    t.index ["user_id"], name: "ix_user_now_playing_user"
  end

  create_table "user_session_tokens", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.boolean "is_dev", default: false, null: false
    t.boolean "is_longstanding", default: false, null: false
    t.string "token", null: false
    t.datetime "updated_at", null: false
    t.string "user_id", null: false
    t.index ["token"], name: "index_user_session_tokens_on_token", unique: true
    t.index ["user_id"], name: "index_user_session_tokens_on_user_id"
  end

  create_table "user_socials", force: :cascade do |t|
    t.datetime "created_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.string "display_text", limit: 80
    t.bigint "platform_id", null: false
    t.datetime "updated_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.string "url", limit: 512
    t.string "user_id", limit: 30, null: false
    t.index "user_id, platform_id, lower((url)::text)", name: "index_user_socials_on_user_platform_url", unique: true, where: "(url IS NOT NULL)"
    t.index ["platform_id"], name: "index_user_socials_on_platform_id"
    t.index ["user_id"], name: "index_user_socials_on_user_id"
  end

  create_table "voting_events", force: :cascade do |t|
    t.integer "attempts", default: 0, null: false
    t.datetime "available_at", null: false
    t.datetime "claimed_until"
    t.datetime "created_at", null: false
    t.datetime "delivered_at"
    t.datetime "expires_at"
    t.string "kind", limit: 64, null: false
    t.jsonb "payload", default: {}, null: false
    t.bigint "round_number", null: false
    t.datetime "updated_at", null: false
    t.index ["available_at"], name: "ix_voting_events_pending", where: "(delivered_at IS NULL)"
    t.index ["round_number", "kind"], name: "ux_voting_events_round_kind", unique: true
  end

  create_table "voting_rounds", primary_key: "round_number", id: :bigint, default: nil, force: :cascade do |t|
    t.datetime "closed_at"
    t.datetime "created_at", null: false
    t.datetime "decided_at"
    t.string "month_year", limit: 200, null: false
    t.jsonb "pending_ties", default: {}, null: false
    t.datetime "runoff_closed_at"
    t.datetime "runoff_closes_at"
    t.datetime "runoff_opens_at"
    t.jsonb "runoff_ties", default: {}, null: false
    t.datetime "updated_at", null: false
    t.datetime "voting_closes_at", null: false
    t.datetime "voting_opens_at", null: false
    t.index ["round_number"], name: "ix_voting_rounds_undecided", where: "(decided_at IS NULL)"
  end

  add_foreign_key "achievement_sets", "gamedb_games", column: "game_id", primary_key: "game_id", name: "fk_achievement_sets_game", on_delete: :nullify
  add_foreign_key "achievements", "achievement_sets", name: "fk_achievements_set", on_delete: :cascade
  add_foreign_key "birthday_posts", "rpg_club_users", column: "user_id", primary_key: "user_id", name: "fk_birthday_posts_user", on_delete: :cascade
  add_foreign_key "bot_jobs", "rpg_club_users", column: "requested_by_user_id", primary_key: "user_id", on_delete: :nullify
  add_foreign_key "challenge_edition_signups", "challenge_editions", column: "edition_id", name: "fk_challenge_edition_signups_edition", on_delete: :cascade
  add_foreign_key "challenge_edition_signups", "gamedb_games", column: "picked_game_id", primary_key: "game_id", name: "fk_challenge_edition_signups_picked_game", on_delete: :nullify
  add_foreign_key "challenge_edition_signups", "rpg_club_users", column: "recipient_user_id", primary_key: "user_id", name: "fk_challenge_edition_signups_recipient", on_delete: :nullify
  add_foreign_key "challenge_edition_signups", "rpg_club_users", column: "user_id", primary_key: "user_id", name: "fk_challenge_edition_signups_user", on_delete: :cascade
  add_foreign_key "challenge_editions", "challenges", name: "fk_challenge_editions_challenge", on_delete: :cascade
  add_foreign_key "challenge_finish_announcements", "challenges", name: "fk_challenge_finish_announcements_challenge", on_delete: :cascade
  add_foreign_key "challenge_finish_announcements", "rpg_club_users", column: "user_id", primary_key: "user_id", name: "fk_challenge_finish_announcements_user", on_delete: :cascade
  add_foreign_key "challenge_lifecycle_steps", "challenges", name: "fk_challenge_lifecycle_steps_challenge", on_delete: :cascade
  add_foreign_key "challenge_pool_collections", "challenges", name: "fk_challenge_pool_collections_challenge", on_delete: :cascade
  add_foreign_key "challenge_pool_collections", "gamedb_collections", column: "collection_id", primary_key: "collection_id", name: "fk_challenge_pool_collections_collection", on_delete: :cascade
  add_foreign_key "challenge_pool_franchises", "challenges", name: "fk_challenge_pool_franchises_challenge", on_delete: :cascade
  add_foreign_key "challenge_pool_franchises", "gamedb_franchises", column: "franchise_id", primary_key: "franchise_id", name: "fk_challenge_pool_franchises_franchise", on_delete: :cascade
  add_foreign_key "challenge_pool_games", "challenges", name: "fk_challenge_pool_games_challenge", on_delete: :cascade
  add_foreign_key "challenge_pool_games", "gamedb_games", column: "game_id", primary_key: "game_id", name: "fk_challenge_pool_games_game", on_delete: :cascade
  add_foreign_key "challenge_pool_list_notices", "challenges", name: "fk_challenge_pool_list_notices_challenge", on_delete: :cascade
  add_foreign_key "challenge_pool_list_notices", "gamedb_games", column: "game_id", primary_key: "game_id", name: "fk_challenge_pool_list_notices_game", on_delete: :cascade
  add_foreign_key "challenge_pool_proposals", "challenges", name: "fk_challenge_pool_proposals_challenge", on_delete: :cascade
  add_foreign_key "challenge_pool_proposals", "gamedb_games", column: "game_id", primary_key: "game_id", name: "fk_challenge_pool_proposals_game", on_delete: :cascade
  add_foreign_key "challenge_pool_proposals", "rpg_club_users", column: "user_id", primary_key: "user_id", name: "fk_challenge_pool_proposals_user", on_delete: :cascade
  add_foreign_key "challenge_run_entries", "challenge_runs", column: "run_id", name: "fk_challenge_run_entries_run", on_delete: :cascade
  add_foreign_key "challenge_run_entries", "gamedb_games", column: "game_id", primary_key: "game_id", name: "fk_challenge_run_entries_game", on_delete: :cascade
  add_foreign_key "challenge_run_entries", "user_game_completions", column: "completion_id", primary_key: "completion_id", name: "fk_challenge_run_entries_completion", on_delete: :nullify
  add_foreign_key "challenge_runs", "challenge_editions", column: "edition_id", name: "fk_challenge_runs_edition", on_delete: :cascade
  add_foreign_key "challenge_runs", "challenges", name: "fk_challenge_runs_challenge", on_delete: :cascade
  add_foreign_key "challenge_runs", "rpg_club_users", column: "user_id", primary_key: "user_id", name: "fk_challenge_runs_user", on_delete: :cascade
  add_foreign_key "challenges", "game_lists", column: "pool_game_list_id", name: "fk_challenges_pool_game_list", on_delete: :nullify
  add_foreign_key "challenges", "rpg_club_users", column: "host_user_id", primary_key: "user_id", name: "fk_challenges_host", on_delete: :nullify
  add_foreign_key "codex_entries", "rpg_club_users", column: "author_user_id", primary_key: "user_id", name: "fk_codex_entries_author"
  add_foreign_key "codex_entry_images", "codex_entries", column: "entry_id", name: "fk_codex_entry_images_entry", on_delete: :cascade
  add_foreign_key "codex_entry_images", "rpg_club_users", column: "uploaded_by_user_id", primary_key: "user_id", name: "fk_codex_entry_images_uploader"
  add_foreign_key "codex_entry_links", "codex_entries", column: "high_entry_id", name: "fk_codex_entry_links_high", on_delete: :cascade
  add_foreign_key "codex_entry_links", "codex_entries", column: "low_entry_id", name: "fk_codex_entry_links_low", on_delete: :cascade
  add_foreign_key "codex_entry_mentions", "codex_entries", column: "entry_id", name: "fk_codex_entry_mentions_entry", on_delete: :cascade
  add_foreign_key "codex_entry_mentions", "rpg_club_users", column: "user_id", primary_key: "user_id", name: "fk_codex_entry_mentions_user", on_delete: :cascade
  add_foreign_key "daily_fun_fact_posts", "codex_entries", column: "entry_id", name: "fk_daily_fun_fact_posts_entry", on_delete: :nullify
  add_foreign_key "game_list_entries", "game_lists", name: "fk_game_list_entries_list", on_delete: :cascade
  add_foreign_key "game_list_entries", "gamedb_games", column: "game_id", primary_key: "game_id", name: "fk_game_list_entries_game", on_delete: :cascade
  add_foreign_key "game_lists", "rpg_club_users", column: "owner_user_id", primary_key: "user_id", name: "fk_game_lists_owner", on_delete: :cascade
  add_foreign_key "game_lists", "rpg_club_users", column: "taken_over_from_user_id", primary_key: "user_id", name: "fk_game_lists_taken_over_from", on_delete: :nullify
  add_foreign_key "gamedb_franchise_changes", "gamedb_games", column: "game_id", primary_key: "game_id", on_delete: :cascade
  add_foreign_key "gamedb_franchise_unlinks", "gamedb_franchises", column: "franchise_id", primary_key: "franchise_id", on_delete: :cascade
  add_foreign_key "gamedb_franchise_unlinks", "gamedb_games", column: "game_id", primary_key: "game_id", on_delete: :cascade
  add_foreign_key "gamedb_franchises", "gamedb_franchises", column: "merged_into_id", primary_key: "franchise_id"
  add_foreign_key "gamedb_game_companies", "gamedb_companies", column: "company_id", primary_key: "company_id", name: "fk_gc_company"
  add_foreign_key "gamedb_game_companies", "gamedb_games", column: "game_id", primary_key: "game_id", name: "fk_gc_game", on_delete: :cascade
  add_foreign_key "gamedb_game_engines", "gamedb_engines", column: "engine_id", primary_key: "engine_id", name: "fk_ge_engine"
  add_foreign_key "gamedb_game_engines", "gamedb_games", column: "game_id", primary_key: "game_id", name: "fk_ge_game", on_delete: :cascade
  add_foreign_key "gamedb_game_franchises", "gamedb_franchises", column: "franchise_id", primary_key: "franchise_id", name: "fk_gf_franchise"
  add_foreign_key "gamedb_game_franchises", "gamedb_games", column: "game_id", primary_key: "game_id", name: "fk_gf_game", on_delete: :cascade
  add_foreign_key "gamedb_game_genres", "gamedb_games", column: "game_id", primary_key: "game_id", name: "fk_gamedb_game_genres_game", on_delete: :cascade
  add_foreign_key "gamedb_game_genres", "gamedb_genres", column: "genre_id", primary_key: "genre_id", name: "fk_gamedb_game_genres_genre"
  add_foreign_key "gamedb_game_images", "gamedb_games", column: "game_id", primary_key: "game_id", name: "fk_rails_gamedb_game_images_game"
  add_foreign_key "gamedb_game_images", "rpg_club_users", column: "uploaded_by_user_id", primary_key: "user_id", name: "fk_rails_gamedb_game_images_uploaded_by"
  add_foreign_key "gamedb_game_modes", "gamedb_game_modes_def", column: "mode_id", primary_key: "mode_id", name: "fk_gm_mode"
  add_foreign_key "gamedb_game_modes", "gamedb_games", column: "game_id", primary_key: "game_id", name: "fk_gm_game", on_delete: :cascade
  add_foreign_key "gamedb_game_perspectives", "gamedb_games", column: "game_id", primary_key: "game_id", name: "fk_gp_game", on_delete: :cascade
  add_foreign_key "gamedb_game_perspectives", "gamedb_perspectives", column: "perspective_id", primary_key: "perspective_id", name: "fk_gp_perspective"
  add_foreign_key "gamedb_game_themes", "gamedb_games", column: "game_id", primary_key: "game_id", name: "fk_gt_game", on_delete: :cascade
  add_foreign_key "gamedb_game_themes", "gamedb_themes", column: "theme_id", primary_key: "theme_id", name: "fk_gt_theme"
  add_foreign_key "gamedb_games", "gamedb_collections", column: "collection_id", primary_key: "collection_id", name: "fk_games_collection"
  add_foreign_key "gamedb_release_announcements", "gamedb_releases", column: "release_id", primary_key: "release_id", name: "fk_gamedb_release_announcements_release"
  add_foreign_key "gamedb_releases", "gamedb_games", column: "game_id", primary_key: "game_id", name: "fk_gamedb_releases_game", on_delete: :cascade
  add_foreign_key "gamedb_releases", "gamedb_platforms", column: "platform_id", primary_key: "platform_id", name: "fk_gamedb_releases_platform"
  add_foreign_key "gamedb_releases", "gamedb_regions", column: "region_id", primary_key: "region_id", name: "fk_gamedb_releases_region"
  add_foreign_key "gamedb_search_synonyms", "gamedb_search_synonym_groups", column: "group_id", primary_key: "group_id", name: "fk_gamedb_search_synonyms_group", on_delete: :cascade
  add_foreign_key "image_backfill_runs", "rpg_club_users", column: "started_by_user_id", primary_key: "user_id", on_delete: :nullify
  add_foreign_key "live_events", "bot_jobs", on_delete: :nullify
  add_foreign_key "live_events", "rpg_club_users", column: "created_by_user_id", primary_key: "user_id", on_delete: :nullify
  add_foreign_key "member_birth_date_changes", "rpg_club_users", column: "user_id", primary_key: "user_id", on_delete: :cascade
  add_foreign_key "member_dashboard_panels", "rpg_club_users", column: "user_id", primary_key: "user_id", on_delete: :cascade
  add_foreign_key "member_feature_preferences", "rpg_club_users", column: "user_id", primary_key: "user_id", on_delete: :cascade
  add_foreign_key "member_hidden_platforms", "gamedb_platforms", column: "platform_id", primary_key: "platform_id", on_delete: :cascade
  add_foreign_key "member_hidden_platforms", "rpg_club_users", column: "user_id", primary_key: "user_id", on_delete: :cascade
  add_foreign_key "member_news_category_preferences", "rpg_club_users", column: "user_id", primary_key: "user_id", on_delete: :cascade
  add_foreign_key "member_pinned_pages", "rpg_club_users", column: "user_id", primary_key: "user_id", on_delete: :cascade
  add_foreign_key "rpg_club_collection_csv_import_items", "rpg_club_collection_csv_imports", column: "import_id", primary_key: "import_id", name: "fk_coll_csv_import_items"
  add_foreign_key "rpg_club_completionator_import_items", "rpg_club_completionator_imports", column: "import_id", primary_key: "import_id", name: "fk_completionator_import_items"
  add_foreign_key "rpg_club_game_keys", "gamedb_games", primary_key: "game_id", name: "fk_rpg_club_game_keys_gamedb", on_delete: :nullify
  add_foreign_key "rpg_club_gamedb_import_items", "rpg_club_gamedb_imports", column: "import_id", primary_key: "import_id", name: "fk_gamedb_import_items"
  add_foreign_key "rpg_club_gotm_audit_items", "rpg_club_gotm_audit_imports", column: "import_id", primary_key: "import_id", name: "fk_gotm_audit_items"
  add_foreign_key "rpg_club_rss_feed_items", "rpg_club_rss_feeds", column: "feed_id", primary_key: "feed_id", name: "fk_rss_feed_items_feed", on_delete: :cascade
  add_foreign_key "rpg_club_steam_collection_import_items", "rpg_club_steam_collection_imports", column: "import_id", primary_key: "import_id", name: "fk_steam_coll_import_items"
  add_foreign_key "rpg_club_suggestion_upvotes", "rpg_club_suggestions", column: "suggestion_id", primary_key: "suggestion_id", name: "fk_rpg_club_suggestion_upvotes_suggestion", on_delete: :cascade
  add_foreign_key "rpg_club_suggestion_upvotes", "rpg_club_users", column: "user_id", primary_key: "user_id", name: "fk_rpg_club_suggestion_upvotes_user", on_delete: :cascade
  add_foreign_key "rpg_club_xbox_collection_import_items", "rpg_club_xbox_collection_imports", column: "import_id", primary_key: "import_id", name: "fk_xbox_coll_import_items"
  add_foreign_key "threads", "gamedb_games", primary_key: "game_id", name: "fk_threads_gamedb_game"
  add_foreign_key "user_achievement_set_progress", "achievement_sets", name: "fk_user_achievement_set_progress_set", on_delete: :cascade
  add_foreign_key "user_achievement_set_progress", "rpg_club_users", column: "user_id", primary_key: "user_id", name: "fk_user_achievement_set_progress_user", on_delete: :cascade
  add_foreign_key "user_achievement_set_progress", "user_linked_accounts", name: "fk_user_achievement_set_progress_linked_account", on_delete: :cascade
  add_foreign_key "user_achievement_unlocks", "achievements", name: "fk_user_achievement_unlocks_achievement", on_delete: :cascade
  add_foreign_key "user_achievement_unlocks", "rpg_club_users", column: "user_id", primary_key: "user_id", name: "fk_user_achievement_unlocks_user", on_delete: :cascade
  add_foreign_key "user_achievement_unlocks", "user_linked_accounts", name: "fk_user_achievement_unlocks_linked_account", on_delete: :cascade
  add_foreign_key "user_franchise_conquests", "gamedb_franchises", column: "franchise_id", primary_key: "franchise_id", on_delete: :cascade
  add_foreign_key "user_franchise_conquests", "rpg_club_users", column: "user_id", primary_key: "user_id", on_delete: :cascade
  add_foreign_key "user_franchise_conquests", "user_game_completions", column: "completion_id", primary_key: "completion_id", on_delete: :nullify
  add_foreign_key "user_game_backlog", "gamedb_games", primary_key: "game_id", name: "fk_user_game_backlog_gamedb"
  add_foreign_key "user_game_backlog", "gamedb_platforms", column: "platform_id", primary_key: "platform_id", name: "fk_user_game_backlog_platform"
  add_foreign_key "user_game_backlog", "rpg_club_users", column: "user_id", primary_key: "user_id", name: "fk_user_game_backlog_user"
  add_foreign_key "user_game_collections", "gamedb_games", primary_key: "game_id", name: "fk_ugcol_gamedb_game"
  add_foreign_key "user_game_collections", "gamedb_platforms", column: "platform_id", primary_key: "platform_id", name: "fk_ugcol_platform"
  add_foreign_key "user_game_completions", "gamedb_games", primary_key: "game_id", name: "fk_ugc_gamedb_game"
  add_foreign_key "user_game_completions", "gamedb_platforms", column: "platform_id", primary_key: "platform_id", name: "fk_user_game_completions_platform"
  add_foreign_key "user_game_favorites", "gamedb_games", primary_key: "game_id", name: "fk_user_game_favorites_gamedb"
  add_foreign_key "user_game_favorites", "rpg_club_users", column: "user_id", primary_key: "user_id", name: "fk_user_game_favorites_user"
  add_foreign_key "user_game_journal_entries", "gamedb_games", primary_key: "game_id", name: "fk_user_game_journal_entries_gamedb"
  add_foreign_key "user_game_journal_entries", "rpg_club_users", column: "user_id", primary_key: "user_id", name: "fk_user_game_journal_entries_user"
  add_foreign_key "user_game_manual_playtimes", "gamedb_games", primary_key: "game_id", on_delete: :cascade
  add_foreign_key "user_game_manual_playtimes", "gamedb_platforms", column: "platform_id", primary_key: "platform_id"
  add_foreign_key "user_game_manual_playtimes", "rpg_club_users", column: "user_id", primary_key: "user_id", on_delete: :cascade
  add_foreign_key "user_game_playthroughs", "gamedb_games", primary_key: "game_id", on_delete: :cascade
  add_foreign_key "user_game_playthroughs", "rpg_club_users", column: "user_id", primary_key: "user_id", on_delete: :cascade
  add_foreign_key "user_game_playthroughs", "user_game_completions", column: "completion_id", primary_key: "completion_id", on_delete: :nullify
  add_foreign_key "user_game_review_revisions", "user_game_reviews", column: "review_id", primary_key: "review_id", name: "fk_user_game_review_revisions_review", on_delete: :cascade
  add_foreign_key "user_game_reviews", "gamedb_games", primary_key: "game_id", name: "fk_user_game_reviews_gamedb"
  add_foreign_key "user_game_reviews", "rpg_club_users", column: "user_id", primary_key: "user_id", name: "fk_user_game_reviews_user"
  add_foreign_key "user_linked_accounts", "rpg_club_users", column: "user_id", primary_key: "user_id", name: "fk_user_linked_accounts_user", on_delete: :cascade
  add_foreign_key "user_now_playing", "gamedb_games", primary_key: "game_id", name: "fk_user_now_playing_gamedb"
  add_foreign_key "user_now_playing", "gamedb_platforms", column: "platform_id", primary_key: "platform_id", name: "fk_user_now_playing_platform"
end
