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

ActiveRecord::Schema[8.1].define(version: 2026_09_10_000100) do
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

  create_table "gamedb_engines", primary_key: "engine_id", force: :cascade do |t|
    t.bigint "igdb_engine_id"
    t.string "name", limit: 255, null: false

    t.unique_constraint ["igdb_engine_id"], name: "gamedb_engines_igdb_engine_id_key"
  end

  create_table "gamedb_franchises", primary_key: "franchise_id", force: :cascade do |t|
    t.bigint "igdb_franchise_id"
    t.string "name", limit: 255, null: false

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
    t.datetime "release_date", precision: 0
    t.index ["game_id"], name: "idx_gamedb_releases_game"
    t.index ["platform_id"], name: "idx_gamedb_releases_platform"
    t.index ["region_id"], name: "idx_gamedb_releases_region"
    t.check_constraint "format::text = ANY (ARRAY['Physical'::character varying::text, 'Digital'::character varying::text])", name: "sys_c009076"
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
    t.string "user_id", limit: 64, null: false
    t.datetime "voted_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.index ["round_number", "nomination_id"], name: "ix_gotm_votes_round_nomination"
    t.index ["round_number", "user_id", "gamedb_game_id"], name: "ux_gotm_votes_round_user_game", unique: true
  end

  create_table "help", primary_key: ["topic", "seq"], force: :cascade do |t|
    t.string "info", limit: 80
    t.bigint "seq", null: false
    t.string "topic", limit: 50, null: false
  end

  create_table "journal_message_contexts", primary_key: ["channel_id", "message_id"], force: :cascade do |t|
    t.string "channel_id", limit: 30, null: false
    t.bigint "created_at_ms", null: false
    t.bigint "game_id", null: false
    t.string "message_id", limit: 30, null: false
    t.string "owner_user_id", limit: 30, null: false
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
    t.string "user_id", limit: 64, null: false
    t.datetime "voted_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.index ["round_number", "nomination_id"], name: "ix_nr_gotm_votes_round_nomination"
    t.index ["round_number", "user_id", "gamedb_game_id"], name: "ux_nr_gotm_votes_round_user_game", unique: true
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
    t.timestamptz "created_at", precision: 6, default: -> { "statement_timestamp()" }, null: false
    t.bigint "current_index", default: 0, null: false
    t.string "source_file_name", limit: 255
    t.bigint "source_file_size"
    t.string "status", limit: 20, null: false
    t.string "template_version", limit: 20
    t.boolean "test_mode", default: false, null: false
    t.bigint "total_count", default: 0, null: false
    t.timestamptz "updated_at", precision: 6, default: -> { "statement_timestamp()" }, null: false
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
    t.timestamptz "created_at", precision: 6, default: -> { "statement_timestamp()" }, null: false
    t.bigint "current_index", default: 0, null: false
    t.string "source_filename", limit: 255
    t.string "status", limit: 20, null: false
    t.boolean "test_mode", default: false, null: false
    t.bigint "total_count", default: 0, null: false
    t.timestamptz "updated_at", precision: 6, default: -> { "statement_timestamp()" }, null: false
    t.string "user_id", limit: 30, null: false
    t.index ["user_id", "status"], name: "ix_completionator_imports_user"
  end

  create_table "rpg_club_game_keys", primary_key: "key_id", force: :cascade do |t|
    t.timestamptz "claimed_at", precision: 6
    t.string "claimed_by_user_id", limit: 30
    t.timestamptz "created_at", precision: 6, default: -> { "statement_timestamp()" }, null: false
    t.boolean "donor_notify_on_claim", default: false, null: false, comment: "1 when the donor requests a notification on claim."
    t.string "donor_user_id", limit: 30, null: false
    t.string "game_title", limit: 200, null: false
    t.bigint "gamedb_game_id"
    t.string "key_value", limit: 200, null: false
    t.string "platform", limit: 50, null: false
    t.timestamptz "updated_at", precision: 6, default: -> { "statement_timestamp()" }, null: false
    t.index ["claimed_by_user_id", "game_title"], name: "ix_game_keys_available"
    t.index ["game_title"], name: "ix_game_keys_title"
    t.index ["gamedb_game_id"], name: "ix_game_keys_game"
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
    t.timestamptz "created_at", precision: 6, default: -> { "statement_timestamp()" }, null: false
    t.string "created_by", limit: 30
    t.bigint "gamedb_game_id"
    t.string "status", limit: 20, null: false
    t.string "title_norm", limit: 500, null: false
    t.string "title_raw", limit: 500, null: false
    t.timestamptz "updated_at", precision: 6, default: -> { "statement_timestamp()" }, null: false
    t.index ["status"], name: "ix_gamedb_import_title_status"
    t.index ["title_norm"], name: "ux_gamedb_import_title_norm", unique: true
  end

  create_table "rpg_club_gamedb_imports", primary_key: "import_id", force: :cascade do |t|
    t.timestamptz "created_at", precision: 6, default: -> { "statement_timestamp()" }, null: false
    t.bigint "current_index", default: 0, null: false
    t.string "source_filename", limit: 255
    t.string "status", limit: 20, null: false
    t.bigint "total_count", default: 0, null: false
    t.timestamptz "updated_at", precision: 6, default: -> { "statement_timestamp()" }, null: false
    t.string "user_id", limit: 30, null: false
    t.index ["user_id", "status"], name: "ix_gamedb_imports_user"
  end

  create_table "rpg_club_gotm_audit_imports", primary_key: "import_id", force: :cascade do |t|
    t.timestamptz "created_at", precision: 6, default: -> { "statement_timestamp()" }, null: false
    t.bigint "current_index", default: 0, null: false
    t.string "source_filename", limit: 255
    t.string "status", limit: 20, null: false
    t.bigint "total_count", default: 0, null: false
    t.timestamptz "updated_at", precision: 6, default: -> { "statement_timestamp()" }, null: false
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
    t.string "single_player", limit: 50
    t.string "source_query", limit: 255
    t.datetime "updated_at", default: -> { "CURRENT_TIMESTAMP" }
    t.string "vs", limit: 50
    t.index ["gamedb_game_id"], name: "uq_hltb_game_id", unique: true
  end

  create_table "rpg_club_presence_prompt_history", primary_key: "prompt_id", id: { type: :string, limit: 64 }, force: :cascade do |t|
    t.timestamptz "created_at", precision: 6, default: -> { "statement_timestamp()" }, null: false
    t.string "game_title", limit: 300, null: false
    t.string "game_title_norm", limit: 300, null: false
    t.timestamptz "resolved_at", precision: 6
    t.string "status", limit: 20, default: "PENDING", null: false
    t.string "user_id", limit: 30, null: false
    t.index ["user_id", "game_title_norm", "status"], name: "idx_rpg_club_presence_prompt_hist_user"
  end

  create_table "rpg_club_presence_prompt_opts", primary_key: ["user_id", "scope", "game_title_norm"], force: :cascade do |t|
    t.timestamptz "created_at", precision: 6, default: -> { "statement_timestamp()" }, null: false
    t.string "game_title", limit: 300
    t.string "game_title_norm", limit: 300, null: false
    t.string "scope", limit: 10, null: false
    t.string "user_id", limit: 30, null: false
    t.check_constraint "scope::text = ANY (ARRAY['ALL'::character varying::text, 'GAME'::character varying::text])", name: "ck_rpg_club_presence_prompt_scope"
  end

  create_table "rpg_club_public_reminders", primary_key: "reminder_id", force: :cascade do |t|
    t.string "channel_id", limit: 30, null: false
    t.timestamptz "created_at", precision: 6, default: -> { "statement_timestamp()" }, null: false
    t.string "created_by", limit: 30
    t.timestamptz "due_at", precision: 6, null: false
    t.boolean "enabled", default: true, null: false
    t.string "message", limit: 2000, null: false
    t.bigint "recur_every"
    t.string "recur_unit", limit: 10
    t.timestamptz "updated_at", precision: 6, default: -> { "statement_timestamp()" }, null: false
    t.index ["due_at", "enabled"], name: "ix_rpg_club_public_reminders_due"
  end

  create_table "rpg_club_raw_modal_sessions", primary_key: "session_id", id: { type: :string, limit: 120 }, force: :cascade do |t|
    t.string "channel_id", limit: 30
    t.timestamptz "created_at", precision: 6, default: -> { "statement_timestamp()" }, null: false
    t.timestamptz "expires_at", precision: 6, null: false
    t.string "feature_id", limit: 60, null: false
    t.string "flow_id", limit: 60, null: false
    t.string "guild_id", limit: 30
    t.string "owner_user_id", limit: 30, null: false
    t.text "state_json", null: false
    t.string "status", limit: 20, default: "OPEN", null: false
    t.timestamptz "updated_at", precision: 6, default: -> { "statement_timestamp()" }, null: false
    t.index ["expires_at"], name: "ix_raw_modal_sess_expires"
    t.index ["owner_user_id", "status"], name: "ix_raw_modal_sess_owner_status"
    t.check_constraint "status::text = ANY (ARRAY['OPEN'::character varying::text, 'SUBMITTED'::character varying::text, 'EXPIRED'::character varying::text])", name: "ck_raw_modal_session_status"
  end

  create_table "rpg_club_rss_feed_items", primary_key: ["feed_id", "item_id_hash"], force: :cascade do |t|
    t.timestamptz "created_at", precision: 6, default: -> { "statement_timestamp()" }, null: false
    t.bigint "feed_id", null: false
    t.string "item_id_hash", limit: 128, null: false
    t.timestamptz "published_at", precision: 6
    t.string "title"
    t.string "url", limit: 2048
  end

  create_table "rpg_club_rss_feeds", primary_key: "feed_id", force: :cascade do |t|
    t.string "channel_id", limit: 30, null: false
    t.timestamptz "created_at", precision: 6, default: -> { "statement_timestamp()" }, null: false
    t.string "exclude_keywords", limit: 4000
    t.string "feed_name", limit: 200
    t.string "feed_url", limit: 512, null: false
    t.string "include_keywords", limit: 4000
    t.timestamptz "updated_at", precision: 6, default: -> { "statement_timestamp()" }, null: false
  end

  create_table "rpg_club_starboard", primary_key: "message_id", id: { type: :string, limit: 30 }, force: :cascade do |t|
    t.string "author_id", limit: 30, null: false
    t.string "channel_id", limit: 30, null: false
    t.timestamptz "created_at", precision: 6, default: -> { "statement_timestamp()" }, null: false
    t.integer "star_count", default: 0, null: false
    t.string "starboard_message_id", limit: 30, null: false
  end

  create_table "rpg_club_steam_app_gamedb_map", primary_key: "map_id", force: :cascade do |t|
    t.timestamptz "created_at", precision: 6, default: -> { "statement_timestamp()" }, null: false
    t.string "created_by", limit: 30
    t.bigint "gamedb_game_id"
    t.string "status", limit: 20, null: false
    t.bigint "steam_app_id", null: false
    t.timestamptz "updated_at", precision: 6, default: -> { "statement_timestamp()" }, null: false
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
    t.timestamptz "created_at", precision: 6, default: -> { "statement_timestamp()" }, null: false
    t.bigint "current_index", default: 0, null: false
    t.string "source_profile_name", limit: 255
    t.string "status", limit: 20, null: false
    t.string "steam_id64", limit: 20, null: false
    t.string "steam_profile_ref", limit: 255
    t.boolean "test_mode", default: false, null: false
    t.bigint "total_count", default: 0, null: false
    t.timestamptz "updated_at", precision: 6, default: -> { "statement_timestamp()" }, null: false
    t.string "user_id", limit: 30, null: false
    t.index ["user_id", "status"], name: "ix_steam_coll_imports_user"
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying::text, 'paused'::character varying::text, 'completed'::character varying::text, 'canceled'::character varying::text])", name: "ck_steam_coll_imports_status"
  end

  create_table "rpg_club_suggestion_review_sessions", primary_key: "session_id", id: { type: :string, limit: 120 }, force: :cascade do |t|
    t.timestamptz "created_at", precision: 6, default: -> { "statement_timestamp()" }, null: false
    t.bigint "current_index", default: 0, null: false
    t.string "reviewer_id", limit: 30, null: false
    t.string "suggestion_ids", limit: 4000, null: false
    t.bigint "total_count", default: 0, null: false
    t.timestamptz "updated_at", precision: 6, default: -> { "statement_timestamp()" }, null: false
    t.index ["created_at"], name: "ix_rpg_club_sug_rev_sess_created"
    t.index ["reviewer_id"], name: "ix_rpg_club_sug_rev_sess_reviewer"
  end

  create_table "rpg_club_suggestions", primary_key: "suggestion_id", force: :cascade do |t|
    t.timestamptz "created_at", precision: 6, default: -> { "statement_timestamp()" }, null: false
    t.string "created_by", limit: 30
    t.string "created_by_name", limit: 100
    t.string "details", limit: 2000
    t.string "labels", limit: 200
    t.string "title", limit: 200, null: false
    t.timestamptz "updated_at", precision: 6, default: -> { "statement_timestamp()" }, null: false
    t.index ["created_at"], name: "ix_rpg_club_suggestions_created"
  end

  create_table "rpg_club_user_avatar_history", primary_key: "event_id", force: :cascade do |t|
    t.binary "avatar_blob"
    t.string "avatar_hash", limit: 128
    t.string "avatar_url", limit: 512
    t.timestamptz "changed_at", precision: 6, default: -> { "statement_timestamp()" }, null: false
    t.string "user_id", limit: 30, null: false
    t.index ["user_id", "changed_at"], name: "ix_rpg_club_user_avatar_history_user"
  end

  create_table "rpg_club_user_nick_history", primary_key: "event_id", force: :cascade do |t|
    t.timestamptz "changed_at", precision: 6, default: -> { "statement_timestamp()" }, null: false
    t.string "new_nick", limit: 100
    t.string "old_nick", limit: 100
    t.string "user_id", limit: 30, null: false
    t.index ["user_id", "changed_at"], name: "ix_rpg_club_user_nick_history_user"
  end

  create_table "rpg_club_users", primary_key: "user_id", id: { type: :string, limit: 30 }, force: :cascade do |t|
    t.binary "avatar_blob"
    t.timestamptz "created_at", precision: 6, default: -> { "statement_timestamp()" }, null: false
    t.string "discord_avatar", limit: 128
    t.boolean "donor_notify_on_claim", default: false, null: false, comment: "1 when the user wants to be notified when a donated key is claimed."
    t.string "emoji_name", limit: 32
    t.string "global_name", limit: 100
    t.boolean "is_bot", default: false, null: false
    t.timestamptz "last_fetched_at", precision: 6
    t.timestamptz "last_seen_at", precision: 6
    t.bigint "message_count", default: 0
    t.binary "profile_image"
    t.timestamptz "profile_image_at", precision: 6
    t.boolean "role_admin", default: false, null: false
    t.boolean "role_member", default: false, null: false
    t.boolean "role_moderator", default: false, null: false
    t.boolean "role_newcomer", default: false, null: false
    t.boolean "role_regular", default: false, null: false
    t.timestamptz "server_joined_at", precision: 6
    t.timestamptz "server_left_at", precision: 6
    t.timestamptz "updated_at", precision: 6, default: -> { "statement_timestamp()" }, null: false
    t.string "username", limit: 100
  end

  create_table "rpg_club_users_hist", primary_key: "history_id", force: :cascade do |t|
    t.string "action_type", limit: 1, null: false
    t.timestamptz "actioned_at", precision: 6, default: -> { "statement_timestamp()" }, null: false
    t.binary "avatar_blob"
    t.string "completionator_url", limit: 512
    t.timestamptz "created_at", precision: 6
    t.boolean "donor_notify_on_claim", comment: "Audit snapshot of donor notification preference."
    t.string "global_name", limit: 100
    t.boolean "is_bot"
    t.timestamptz "last_fetched_at", precision: 6
    t.timestamptz "last_seen_at", precision: 6
    t.bigint "message_count"
    t.string "nsw_friend_code", limit: 50
    t.binary "profile_image"
    t.timestamptz "profile_image_at", precision: 6
    t.string "psn_username", limit: 100
    t.boolean "role_admin"
    t.boolean "role_member"
    t.boolean "role_moderator"
    t.boolean "role_newcomer"
    t.boolean "role_regular"
    t.timestamptz "server_joined_at", precision: 6
    t.timestamptz "server_left_at", precision: 6
    t.string "steam_url", limit: 512
    t.timestamptz "updated_at", precision: 6
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
    t.timestamptz "created_at", precision: 6, default: -> { "statement_timestamp()" }, null: false
    t.bigint "current_index", default: 0, null: false
    t.string "gamertag", limit: 100
    t.string "source_file_name", limit: 255
    t.bigint "source_file_size"
    t.string "source_type", limit: 20, null: false
    t.string "status", limit: 20, null: false
    t.string "template_version", limit: 20
    t.bigint "total_count", default: 0, null: false
    t.timestamptz "updated_at", precision: 6, default: -> { "statement_timestamp()" }, null: false
    t.string "user_id", limit: 30, null: false
    t.string "xuid", limit: 30
    t.index ["user_id", "status"], name: "ix_xbox_coll_imports_user"
    t.check_constraint "source_type::text = ANY (ARRAY['API'::character varying::text, 'CSV'::character varying::text])", name: "ck_xbox_coll_imports_source"
    t.check_constraint "status::text = ANY (ARRAY['ACTIVE'::character varying::text, 'PAUSED'::character varying::text, 'COMPLETED'::character varying::text, 'CANCELED'::character varying::text])", name: "ck_xbox_coll_imports_status"
  end

  create_table "rpg_club_xbox_title_gamedb_map", primary_key: "map_id", force: :cascade do |t|
    t.timestamptz "created_at", precision: 6, default: -> { "statement_timestamp()" }, null: false
    t.string "created_by", limit: 30
    t.bigint "gamedb_game_id"
    t.string "status", limit: 20, null: false
    t.timestamptz "updated_at", precision: 6, default: -> { "statement_timestamp()" }, null: false
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
    t.timestamptz "linked_at", precision: 6, default: -> { "statement_timestamp()" }, null: false
    t.string "thread_id", limit: 50, null: false
    t.index ["gamedb_game_id"], name: "ix_thread_game_links_game"
  end

  create_table "threads", primary_key: "thread_id", id: { type: :string, limit: 30 }, force: :cascade do |t|
    t.timestamptz "created_at", precision: 6, default: -> { "statement_timestamp()" }, null: false
    t.string "forum_channel_id", limit: 30, null: false
    t.bigint "gamedb_game_id"
    t.string "is_archived", limit: 1, default: "N", null: false
    t.timestamptz "last_seen_at", precision: 6
    t.string "skip_linking", limit: 1, default: "N", null: false
    t.string "thread_name", limit: 200, null: false
    t.index ["forum_channel_id"], name: "ix_threads_forum"
    t.index ["gamedb_game_id"], name: "ix_threads_gamedb"
    t.check_constraint "is_archived::text = ANY (ARRAY['Y'::character varying::text, 'N'::character varying::text])", name: "ck_threads_is_archived"
    t.check_constraint "skip_linking::text = ANY (ARRAY['Y'::character varying::text, 'N'::character varying::text])", name: "ck_threads_skip_linking"
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
    t.index ["gamedb_game_id"], name: "ix_ugc_game"
    t.index ["platform_id"], name: "idx_user_game_completions_platform"
    t.index ["user_id"], name: "ix_ugc_user"
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

  create_table "user_game_reviews", primary_key: "review_id", force: :cascade do |t|
    t.jsonb "body"
    t.datetime "created_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.jsonb "facets"
    t.bigint "gamedb_game_id", null: false
    t.boolean "is_shared", default: true, null: false
    t.integer "rating", null: false
    t.datetime "updated_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.string "user_id", limit: 50, null: false
    t.index ["gamedb_game_id"], name: "ix_user_game_reviews_game"
    t.index ["user_id", "gamedb_game_id"], name: "uq_user_game_reviews_user_game", unique: true
    t.index ["user_id"], name: "ix_user_game_reviews_user"
    t.check_constraint "rating >= 0 AND rating <= 100", name: "ck_user_game_reviews_rating_range"
  end

  create_table "user_now_playing", primary_key: "entry_id", force: :cascade do |t|
    t.timestamptz "added_at", precision: 6, default: -> { "statement_timestamp()" }, null: false
    t.bigint "gamedb_game_id"
    t.string "note", limit: 500
    t.timestamptz "note_updated_at", precision: 6
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
  add_foreign_key "rpg_club_collection_csv_import_items", "rpg_club_collection_csv_imports", column: "import_id", primary_key: "import_id", name: "fk_coll_csv_import_items"
  add_foreign_key "rpg_club_completionator_import_items", "rpg_club_completionator_imports", column: "import_id", primary_key: "import_id", name: "fk_completionator_import_items"
  add_foreign_key "rpg_club_game_keys", "gamedb_games", primary_key: "game_id", name: "fk_rpg_club_game_keys_gamedb", on_delete: :nullify
  add_foreign_key "rpg_club_gamedb_import_items", "rpg_club_gamedb_imports", column: "import_id", primary_key: "import_id", name: "fk_gamedb_import_items"
  add_foreign_key "rpg_club_gotm_audit_items", "rpg_club_gotm_audit_imports", column: "import_id", primary_key: "import_id", name: "fk_gotm_audit_items"
  add_foreign_key "rpg_club_rss_feed_items", "rpg_club_rss_feeds", column: "feed_id", primary_key: "feed_id", name: "fk_rss_feed_items_feed"
  add_foreign_key "rpg_club_steam_collection_import_items", "rpg_club_steam_collection_imports", column: "import_id", primary_key: "import_id", name: "fk_steam_coll_import_items"
  add_foreign_key "rpg_club_xbox_collection_import_items", "rpg_club_xbox_collection_imports", column: "import_id", primary_key: "import_id", name: "fk_xbox_coll_import_items"
  add_foreign_key "threads", "gamedb_games", primary_key: "game_id", name: "fk_threads_gamedb_game"
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
  add_foreign_key "user_game_reviews", "gamedb_games", primary_key: "game_id", name: "fk_user_game_reviews_gamedb"
  add_foreign_key "user_game_reviews", "rpg_club_users", column: "user_id", primary_key: "user_id", name: "fk_user_game_reviews_user"
  add_foreign_key "user_now_playing", "gamedb_games", primary_key: "game_id", name: "fk_user_now_playing_gamedb"
  add_foreign_key "user_now_playing", "gamedb_platforms", column: "platform_id", primary_key: "platform_id", name: "fk_user_now_playing_platform"
end
