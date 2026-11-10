# frozen_string_literal: true

# Sets every Feature that existed when Feature Flags shipped to Live, so the
# release changes nothing anyone sees (spec #347), and logs each as a change
# by "system". The keys are listed here rather than read from
# Features::REGISTRY on purpose: a Feature registered later has no stored
# state and so starts in Preview. A Feature that already has a state keeps
# it, so re-running is a no-op.
class SeedFeatureFlagsLive < ActiveRecord::Migration[8.1]
  KEYS = %w[
    game_index voting_gotm backlog collection now_playing game_completions
    reviews achievement_hub giveaways journals suggestions
  ].freeze

  def up
    keys = KEYS.map { |key| connection.quote(key) }.join(", ")
    execute <<~SQL.squish
      WITH seeded AS (
        INSERT INTO feature_flags (key, state, created_at, updated_at)
        SELECT key, 'live', NOW(), NOW() FROM unnest(ARRAY[#{keys}]) AS key
        ON CONFLICT (key) DO NOTHING
        RETURNING key
      )
      INSERT INTO feature_flag_changes (feature_key, from_state, to_state, changed_by, reason, created_at)
      SELECT key, NULL, 'live', 'system', 'Feature Flags shipped with every Feature Live', NOW() FROM seeded
    SQL
  end

  # The change log is append-only, so the seed stays; rolling back
  # CreateFeatureFlags drops it with the tables.
  def down; end
end
