# frozen_string_literal: true

# Mirrors the Steam collection import's test_mode column (#166) onto
# RpgClubCollectionCsvImport, so the bot's collection-csv-import command can
# support a dry-run mode too (#187).
class AddTestModeToRpgClubCollectionCsvImports < ActiveRecord::Migration[8.1]
  def change
    add_column :rpg_club_collection_csv_imports, :test_mode, :boolean, default: false, null: false
  end
end
