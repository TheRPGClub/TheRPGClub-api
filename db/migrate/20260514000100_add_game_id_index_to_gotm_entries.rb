# frozen_string_literal: true

class AddGameIdIndexToGotmEntries < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    add_index :gotm_entries, :gamedb_game_id,
      name: :idx_gotm_entries_game,
      if_not_exists: true,
      algorithm: :concurrently
    add_index :nr_gotm_entries, :gamedb_game_id,
      name: :idx_nr_gotm_entries_game,
      if_not_exists: true,
      algorithm: :concurrently
  end

  def down
    remove_index :gotm_entries,
      name: :idx_gotm_entries_game,
      if_exists: true,
      algorithm: :concurrently
    remove_index :nr_gotm_entries,
      name: :idx_nr_gotm_entries_game,
      if_exists: true,
      algorithm: :concurrently
  end
end
