# frozen_string_literal: true

# Hidden Platforms (spec api#421, ticket api#427; GLOSSARY.md "Hidden
# Platform"): the platforms a member leaves out of their own Release Calendar
# and Upcoming Releases panel. One row per member and platform; a platform
# removed from GameDB drops out of every member's set with it.
class CreateMemberHiddenPlatforms < ActiveRecord::Migration[8.1]
  def change
    create_table :member_hidden_platforms do |t|
      t.string :user_id, limit: 30, null: false
      t.bigint :platform_id, null: false
      t.datetime :created_at, null: false
    end

    add_index :member_hidden_platforms, %i[user_id platform_id], unique: true
    add_foreign_key :member_hidden_platforms, :rpg_club_users, column: :user_id, primary_key: :user_id,
      on_delete: :cascade
    add_foreign_key :member_hidden_platforms, :gamedb_platforms, column: :platform_id, primary_key: :platform_id,
      on_delete: :cascade
  end
end
