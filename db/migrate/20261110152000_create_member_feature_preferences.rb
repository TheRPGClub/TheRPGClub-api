# frozen_string_literal: true

# Feature Preferences (spec #347, ticket #352): a member's choice to hide a
# hideable Feature from their own view of the website. Opt-out: one row per
# member per hidden Feature, so a member with no rows sees everything. The
# Feature key is not tied to the Feature Flag row, so a preference survives
# any flag change.
class CreateMemberFeaturePreferences < ActiveRecord::Migration[8.1]
  def change
    create_table :member_feature_preferences do |t|
      t.string :user_id, limit: 30, null: false
      t.string :feature_key, limit: 64, null: false
      t.datetime :created_at, null: false
    end

    add_index :member_feature_preferences, %i[user_id feature_key], unique: true
    add_foreign_key :member_feature_preferences, :rpg_club_users, column: :user_id, primary_key: :user_id,
      on_delete: :cascade
  end
end
