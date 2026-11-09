# frozen_string_literal: true

# Rewrites every GameDB title that starts with The/A/An to "X, The" so titles
# sort by their first significant word (docs/adr/0004). New and edited titles
# get the same rule from GamedbGame's before_validation
# (Gamedb::TitleArticle.to_end); this regexp mirrors it. Re-running is a no-op.
class MoveLeadingArticlesToEndOfGameTitles < ActiveRecord::Migration[8.1]
  def up
    execute <<~'SQL'.squish
      UPDATE gamedb_games
      SET title = regexp_replace(btrim(title), '^(the|a|an)\s+(.*\S)$', '\2, \1', 'i'),
          updated_at = NOW()
      WHERE btrim(title) ~* '^(the|a|an)\s+.*\S$'
    SQL
    bump_relations_cache
  end

  def down
    execute <<~'SQL'.squish
      UPDATE gamedb_games
      SET title = regexp_replace(btrim(title), '^(.*\S),\s*(the|a|an)$', '\2 \1', 'i'),
          updated_at = NOW()
      WHERE btrim(title) ~* '^.*\S,\s*(the|a|an)$'
    SQL
    bump_relations_cache
  end

  private

  # Other games cache these titles in their `alternates` slice. That cache
  # also expires on its own within 12 hours, so a cache store that is not
  # reachable from the release machine must not fail the deploy.
  def bump_relations_cache
    Gamedb::GameRelationsCacheVersion.bump!
  rescue StandardError => error
    say "relations cache not bumped (#{error.class}: #{error.message}); it expires within 12 hours"
  end
end
