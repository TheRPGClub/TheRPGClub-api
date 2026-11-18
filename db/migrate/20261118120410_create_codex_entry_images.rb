# frozen_string_literal: true

# Club Codex entry images (spec #397, ticket #410): a gallery of up to 4
# images on a History Event or Lore Entry, each file kept in the same
# Backblaze bucket as the GameDB game images under `object_key`.
#
#   position              1 to 4, in upload order; when one is removed the
#                         later ones move up, so a gallery is always 1..n.
#                         Unique per entry, checked at commit so that move
#                         can run as one statement
#   uploaded_by_user_id   the member who added it
#
# Rows go with their entry (the app removes the files from storage first).
class CreateCodexEntryImages < ActiveRecord::Migration[8.1]
  def change
    create_table :codex_entry_images do |t|
      t.bigint :entry_id, null: false
      t.string :object_key, null: false
      t.integer :position, limit: 2, null: false
      t.string :uploaded_by_user_id, limit: 30, null: false
      t.timestamps

      t.check_constraint "position BETWEEN 1 AND 4", name: "ck_codex_entry_images_position"
      t.unique_constraint %i[entry_id position], deferrable: :deferred, name: "uq_codex_entry_images_entry_position"
      t.index :object_key, unique: true, name: "ux_codex_entry_images_object_key"
      t.index :uploaded_by_user_id, name: "ix_codex_entry_images_uploader"
    end
    add_foreign_key :codex_entry_images, :codex_entries, column: :entry_id, on_delete: :cascade,
      name: "fk_codex_entry_images_entry"
    add_foreign_key :codex_entry_images, :rpg_club_users, column: :uploaded_by_user_id, primary_key: :user_id,
      name: "fk_codex_entry_images_uploader"
  end
end
