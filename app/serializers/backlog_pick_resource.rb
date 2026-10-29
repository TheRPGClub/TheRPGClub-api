# frozen_string_literal: true

# The entry chosen by backlog#pick (BacklogPicker::Pick): whether it came from
# the backlog or the collection, the entry's columns, its game and platform, the
# HLTB cache row (null when the game has none) and the parsed `hours` the
# `max_hours` filter compares (null when HLTB has no usable time).
class BacklogPickResource
  include BaseResource

  attribute(:kind, &:kind)
  attribute(:entry_id) { |pick| pick.entry.entry_id }
  attribute(:gamedb_game_id) { |pick| pick.entry.gamedb_game_id }
  attribute(:platform_id) { |pick| pick.entry.platform_id }
  attribute(:note) { |pick| pick.entry.note }
  attribute(:hours, &:hours)
  attribute(:game) { |pick| GameSummaryResource.new(pick.entry.game).serializable_hash }
  attribute(:platform) { |pick| pick.entry.platform && PlatformResource.new(pick.entry.platform).serializable_hash }
  attribute(:hltb) { |pick| pick.hltb && HltbResource.new(pick.hltb).serializable_hash }
end
