# frozen_string_literal: true

# Feedback linked to Roadmap Items (spec api#505, ticket api#508). An item
# links any number of Feedback; a Feedback sits on at most one item (unique
# on `feedback_id`). Deleting the item or the Feedback removes the link.
class CreateRoadmapItemFeedback < ActiveRecord::Migration[8.1]
  def change
    create_table :roadmap_item_feedback do |t|
      t.bigint :item_id, null: false
      t.bigint :feedback_id, null: false
      t.timestamptz :created_at, null: false, default: -> { "statement_timestamp()" }
    end
    add_index :roadmap_item_feedback, :feedback_id, unique: true, name: "ux_roadmap_item_feedback_feedback"
    add_index :roadmap_item_feedback, :item_id, name: "ix_roadmap_item_feedback_item"
    add_foreign_key :roadmap_item_feedback, :roadmap_items, column: :item_id,
      on_delete: :cascade, name: "fk_roadmap_item_feedback_item"
    add_foreign_key :roadmap_item_feedback, :rpg_club_feedback, column: :feedback_id, primary_key: :feedback_id,
      on_delete: :cascade, name: "fk_roadmap_item_feedback_feedback"
  end
end
