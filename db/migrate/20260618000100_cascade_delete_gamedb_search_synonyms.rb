# frozen_string_literal: true

# Makes `gamedb_search_synonyms.group_id` cascade-delete: removing a synonym
# group now also removes its terms (therpgclub-api #108). Previously the FK had
# no `ON DELETE CASCADE`, so deleting a non-empty group raised a foreign-key
# violation and callers had to delete the terms first.
#
# Lockstep with the bot's `GameSearchSynonym` migration (TheRPGClub-bot #854):
# its `deleteGroup` can drop the manual term-deletion step and just delete the
# group. The bulk `DELETE /api/v1/search_synonym_groups/:id/terms` endpoint (also
# in #108) still covers the *replace-terms* flow, where the group is kept.
class CascadeDeleteGamedbSearchSynonyms < ActiveRecord::Migration[8.1]
  TABLE = :gamedb_search_synonyms
  FK_NAME = "fk_gamedb_search_synonyms_group"

  def up
    remove_foreign_key TABLE, name: FK_NAME if foreign_key_exists?(TABLE, name: FK_NAME)
    add_foreign_key TABLE, :gamedb_search_synonym_groups,
      column: :group_id, primary_key: :group_id,
      name: FK_NAME, on_delete: :cascade
  end

  def down
    remove_foreign_key TABLE, name: FK_NAME if foreign_key_exists?(TABLE, name: FK_NAME)
    add_foreign_key TABLE, :gamedb_search_synonym_groups,
      column: :group_id, primary_key: :group_id,
      name: FK_NAME
  end
end
