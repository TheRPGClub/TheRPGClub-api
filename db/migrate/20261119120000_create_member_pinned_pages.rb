# frozen_string_literal: true

# Pinned Pages (spec api#416, ticket api#418; docs/adr/0012): the pages a
# member put at the top of their own sidebar, in their order. A member with no
# saved list follows the club default (PinnedPages::DEFAULT); their first save
# writes their whole list and sets `pinned_pages_customised`, so a member who
# unpinned everything keeps an empty list rather than falling back to the
# default. `page_key` is a PinnedPages key, not tied to any
# other table, so a pin survives its page being hidden for a while.
class CreateMemberPinnedPages < ActiveRecord::Migration[8.1]
  def change
    create_table :member_pinned_pages do |t|
      t.string :user_id, limit: 30, null: false
      t.string :page_key, limit: 64, null: false
      t.integer :position, null: false
      t.datetime :created_at, null: false
    end

    add_index :member_pinned_pages, %i[user_id page_key], unique: true
    add_foreign_key :member_pinned_pages, :rpg_club_users, column: :user_id, primary_key: :user_id,
      on_delete: :cascade

    add_column :rpg_club_users, :pinned_pages_customised, :boolean, default: false, null: false,
      comment: "Whether the member saved their own Pinned Pages; false follows the club default."
  end
end
