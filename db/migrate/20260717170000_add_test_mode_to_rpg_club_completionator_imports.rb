# frozen_string_literal: true

# Mirrors the Steam collection import's test_mode column (#166) and the
# collection CSV import's test_mode column (#187) onto
# RpgClubCompletionatorImport, so the bot's import-completionator command can
# support a dry-run mode too (#188).
class AddTestModeToRpgClubCompletionatorImports < ActiveRecord::Migration[8.1]
  def change
    add_column :rpg_club_completionator_imports, :test_mode, :boolean, default: false, null: false
  end
end
