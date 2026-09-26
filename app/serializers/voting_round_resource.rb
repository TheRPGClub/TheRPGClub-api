# frozen_string_literal: true

# A voting round with its derived lifecycle state. `phase` is the server's
# verdict at render time (nominating -> voting -> closed | tie -> decided) and
# the booleans restate it for the common checks, so clients never re-derive
# the windows from the timestamps. `pending_ties` embeds each tied game (the
# GameSummaryResource shape) so an admin prompt can render the choice without
# a lookup per game.
class VotingRoundResource
  include BaseResource

  attributes :round_number, :month_year, :voting_opens_at, :voting_closes_at, :closed_at, :decided_at

  attribute :phase do |round|
    round.phase
  end

  attribute :nominations_open do |round|
    round.nominations_open?
  end

  attribute :voting_open do |round|
    round.voting_open?
  end

  attribute :voting_ended do |round|
    round.voting_ended?
  end

  attribute :pending_ties do |round|
    ids = round.pending_ties.values.flatten
    games = ids.empty? ? {} : GamedbGame.where(game_id: ids).preload(:images).index_by(&:game_id)
    round.pending_ties.transform_values do |game_ids|
      game_ids.filter_map { |id| games[id] }.map { |game| GameSummaryResource.new(game).serializable_hash }
    end
  end
end
