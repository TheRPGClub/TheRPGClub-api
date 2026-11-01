# frozen_string_literal: true

# The Achievement Hub's data model (spec: specs/achievement-hub, ADRs
# 0001-0003). Achievement Sets and Achievements are shared, Provider-scoped
# definitions; a member's Unlocks and cached per-set progress hang off their
# Linked Account and cascade away when it is unlinked, while the definitions
# stay. Sync state lives here rather than in the queue, which is recreated on
# every deploy (ADR 0003).
class CreateAchievementHub < ActiveRecord::Migration[8.1]
  def change
    create_table :user_linked_accounts do |t|
      t.string :user_id, limit: 30, null: false
      t.string :provider, limit: 32, null: false
      # RA ULID, SteamID64 or PSN accountId: never a renameable name.
      t.string :external_id, limit: 64, null: false
      t.string :display_name, limit: 255
      t.string :sync_status, limit: 32, null: false, default: "pending"
      t.text :sync_error
      # Set while the account waits for a listing; cleared once it has run.
      t.datetime :sync_due_at, precision: 6
      t.string :sync_mode, limit: 32, null: false, default: "backfill"
      t.datetime :backfilled_at, precision: 6
      t.datetime :last_synced_at, precision: 6
      # When the member last pressed "Sync now" (15-minute cooldown).
      t.datetime :sync_requested_at, precision: 6
      t.timestamps
    end
    add_index :user_linked_accounts, %i[provider external_id], unique: true,
      name: "ux_user_linked_accounts_provider_external"
    add_index :user_linked_accounts, %i[user_id provider], unique: true,
      name: "ux_user_linked_accounts_user_provider"
    add_index :user_linked_accounts, %i[provider sync_due_at], where: "sync_due_at IS NOT NULL",
      name: "ix_user_linked_accounts_sync_due"
    add_foreign_key :user_linked_accounts, :rpg_club_users, column: :user_id, primary_key: :user_id,
      on_delete: :cascade, name: "fk_user_linked_accounts_user"

    create_table :achievement_sets do |t|
      t.string :provider, limit: 32, null: false
      # RA game id, Steam appid or PSN npCommunicationId.
      t.string :external_id, limit: 64, null: false
      # PSN only: "trophy" (PS3/PS4/Vita) or "trophy2" (PS5).
      t.string :np_service_name, limit: 32
      t.string :title, limit: 512
      t.string :platform_label, limit: 100
      t.string :icon_url, limit: 1024
      t.bigint :game_id
      t.integer :achievements_count, null: false, default: 0
      t.integer :points_total, null: false, default: 0
      t.datetime :definitions_synced_at, precision: 6
      t.timestamps
    end
    add_index :achievement_sets, %i[provider external_id], unique: true,
      name: "ux_achievement_sets_provider_external"
    add_index :achievement_sets, :game_id, name: "ix_achievement_sets_game"
    add_foreign_key :achievement_sets, :gamedb_games, column: :game_id, primary_key: :game_id,
      on_delete: :nullify, name: "fk_achievement_sets_game"

    create_table :achievements do |t|
      t.bigint :achievement_set_id, null: false
      t.string :external_id, limit: 64, null: false
      t.string :name, limit: 512
      t.text :description
      t.string :icon_url, limit: 1024
      t.string :icon_locked_url, limit: 1024
      t.boolean :hidden, null: false, default: false
      # RetroAchievements only.
      t.integer :points
      # PSN only.
      t.string :tier, limit: 16
      t.integer :display_order
      # The Provider's global Rarity, in percent.
      t.decimal :rarity, precision: 5, scale: 2
      # RetroAchievements only.
      t.decimal :rarity_hardcore, precision: 5, scale: 2
      # Set when the Provider stops reporting it. Never deleted: that would
      # cascade to every member's Unlocks.
      t.datetime :removed_at, precision: 6
      t.timestamps
    end
    add_index :achievements, %i[achievement_set_id external_id], unique: true,
      name: "ux_achievements_set_external"
    add_foreign_key :achievements, :achievement_sets, on_delete: :cascade, name: "fk_achievements_set"

    create_table :user_achievement_unlocks do |t|
      t.string :user_id, limit: 30, null: false
      t.bigint :achievement_id, null: false
      t.bigint :user_linked_account_id, null: false
      t.datetime :unlocked_at, precision: 6, null: false
      t.boolean :hardcore, null: false, default: false
      t.string :highlight, limit: 16
      t.boolean :announceable, null: false, default: false
      t.timestamps
    end
    add_index :user_achievement_unlocks, %i[user_id achievement_id], unique: true,
      name: "ux_user_achievement_unlocks_user_achievement"
    add_index :user_achievement_unlocks, :unlocked_at, name: "ix_user_achievement_unlocks_unlocked_at"
    add_index :user_achievement_unlocks, :id, where: "announceable",
      name: "ix_user_achievement_unlocks_announceable"
    add_index :user_achievement_unlocks, :achievement_id, name: "ix_user_achievement_unlocks_achievement"
    add_index :user_achievement_unlocks, :user_linked_account_id,
      name: "ix_user_achievement_unlocks_linked_account"
    add_foreign_key :user_achievement_unlocks, :rpg_club_users, column: :user_id, primary_key: :user_id,
      on_delete: :cascade, name: "fk_user_achievement_unlocks_user"
    add_foreign_key :user_achievement_unlocks, :achievements, on_delete: :cascade,
      name: "fk_user_achievement_unlocks_achievement"
    add_foreign_key :user_achievement_unlocks, :user_linked_accounts, on_delete: :cascade,
      name: "fk_user_achievement_unlocks_linked_account"

    create_table :user_achievement_set_progress do |t|
      t.string :user_id, limit: 30, null: false
      t.bigint :achievement_set_id, null: false
      t.bigint :user_linked_account_id, null: false
      t.integer :earned_count, null: false, default: 0
      t.integer :hardcore_earned_count, null: false, default: 0
      t.integer :total_count, null: false, default: 0
      t.integer :points_earned, null: false, default: 0
      t.datetime :completed_at, precision: 6
      t.datetime :mastered_at, precision: 6
      t.datetime :platinum_at, precision: 6
      t.datetime :last_unlocked_at, precision: 6
      t.integer :playtime_minutes
      # Set while the set waits for an import.
      t.datetime :sync_pending_at, precision: 6
      # Nil on a placeholder row, which every read excludes.
      t.datetime :synced_at, precision: 6
      t.timestamps
    end
    add_index :user_achievement_set_progress, %i[user_id achievement_set_id], unique: true,
      name: "ux_user_achievement_set_progress_user_set"
    add_index :user_achievement_set_progress, %i[user_id last_unlocked_at],
      name: "ix_user_achievement_set_progress_user_last_unlocked"
    add_index :user_achievement_set_progress, :sync_pending_at, where: "sync_pending_at IS NOT NULL",
      name: "ix_user_achievement_set_progress_sync_pending"
    add_index :user_achievement_set_progress, :achievement_set_id,
      name: "ix_user_achievement_set_progress_set"
    add_index :user_achievement_set_progress, :user_linked_account_id,
      name: "ix_user_achievement_set_progress_linked_account"
    add_foreign_key :user_achievement_set_progress, :rpg_club_users, column: :user_id, primary_key: :user_id,
      on_delete: :cascade, name: "fk_user_achievement_set_progress_user"
    add_foreign_key :user_achievement_set_progress, :achievement_sets, on_delete: :cascade,
      name: "fk_user_achievement_set_progress_set"
    add_foreign_key :user_achievement_set_progress, :user_linked_accounts, on_delete: :cascade,
      name: "fk_user_achievement_set_progress_linked_account"

    # Small key/value store: the bot's Highlight cursor, psn_auth_expired_at.
    create_table :achievement_hub_states do |t|
      t.string :key, limit: 100, null: false
      t.jsonb :value
      t.timestamps
    end
    add_index :achievement_hub_states, :key, unique: true, name: "ux_achievement_hub_states_key"
  end
end
