# frozen_string_literal: true

# One upvote per member per Suggestion (web parity 2, #318). Removed with the
# Suggestion or the member.
class CreateRpgClubSuggestionUpvotes < ActiveRecord::Migration[8.1]
  def change
    create_table :rpg_club_suggestion_upvotes do |t|
      t.bigint :suggestion_id, null: false
      t.string :user_id, limit: 30, null: false
      t.timestamptz :created_at, null: false, default: -> { "statement_timestamp()" }
    end
    add_index :rpg_club_suggestion_upvotes, %i[suggestion_id user_id], unique: true,
      name: "ux_rpg_club_suggestion_upvotes_suggestion_user"
    add_index :rpg_club_suggestion_upvotes, :user_id, name: "ix_rpg_club_suggestion_upvotes_user"
    add_foreign_key :rpg_club_suggestion_upvotes, :rpg_club_suggestions, column: :suggestion_id,
      primary_key: :suggestion_id, on_delete: :cascade, name: "fk_rpg_club_suggestion_upvotes_suggestion"
    add_foreign_key :rpg_club_suggestion_upvotes, :rpg_club_users, column: :user_id,
      primary_key: :user_id, on_delete: :cascade, name: "fk_rpg_club_suggestion_upvotes_user"
  end
end
