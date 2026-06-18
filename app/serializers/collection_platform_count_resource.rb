# frozen_string_literal: true

# A single per-platform tally for collections#platform_summary: the platform
# identity (all null for the entries with no platform) and the `count` of the
# user's entries on it. Not a plain model record — the controller hands in
# grouped aggregate rows (the `platform_id` column, the joined platform
# name/abbreviation and the `COUNT(*)` `count` alias), read the same defensive
# `row["..."]` way CompletionLeaderboardEntryResource reads its grouped aggregates.
class CollectionPlatformCountResource
  include BaseResource

  attribute(:platform_id) { |row| row["platform_id"] }
  attribute(:platform_name) { |row| row["platform_name"] }
  attribute(:platform_abbreviation) { |row| row["platform_abbreviation"] }
  attribute(:count) { |row| row["count"].to_i }
end
