# frozen_string_literal: true

# Feature Flags (spec #347, docs/adr/0005). The list of Features lives in
# code (Features::REGISTRY); only each Feature Flag's state is stored here, one
# row per Feature key. A registered key with no row reads as Preview.
# feature_flag_changes is the append-only log of every state change: who made
# it ("system" or a Discord user id), from and to which state, and why.
class CreateFeatureFlags < ActiveRecord::Migration[8.1]
  def change
    create_table :feature_flags do |t|
      t.string :key, limit: 64, null: false
      t.string :state, limit: 16, null: false
      t.timestamps
    end

    add_index :feature_flags, :key, unique: true
    add_check_constraint :feature_flags, "state IN ('off', 'preview', 'live')", name: "ck_feature_flags_state"

    create_table :feature_flag_changes do |t|
      t.string :feature_key, limit: 64, null: false
      t.string :from_state, limit: 16
      t.string :to_state, limit: 16, null: false
      t.string :changed_by, limit: 30, null: false
      t.text :reason
      t.datetime :created_at, null: false
    end

    add_index :feature_flag_changes, %i[feature_key created_at]
    add_check_constraint :feature_flag_changes, "from_state IS NULL OR from_state IN ('off', 'preview', 'live')",
      name: "ck_feature_flag_changes_from_state"
    add_check_constraint :feature_flag_changes, "to_state IN ('off', 'preview', 'live')",
      name: "ck_feature_flag_changes_to_state"
  end
end
