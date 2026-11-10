# frozen_string_literal: true

# News Category Preferences (spec #355, ticket #357): a member's choice to
# leave a News Category out of their own default view of the News Hub.
# Mirrors member_feature_preferences: one row per member per switched-off
# News Category, so a member with no rows sees every category. The key is not
# checked against the list in code, so a row for a category that is later
# removed is simply ignored.
class CreateMemberNewsCategoryPreferences < ActiveRecord::Migration[8.1]
  def change
    create_table :member_news_category_preferences do |t|
      t.string :user_id, limit: 30, null: false
      t.string :category_key, limit: 64, null: false
      t.datetime :created_at, null: false
    end

    add_index :member_news_category_preferences, %i[user_id category_key], unique: true,
      name: "index_member_news_category_preferences_on_user_and_category"
    add_foreign_key :member_news_category_preferences, :rpg_club_users, column: :user_id, primary_key: :user_id,
      on_delete: :cascade
  end
end
