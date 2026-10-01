# frozen_string_literal: true

# A voting round with its derived lifecycle state. `phase` is the server's
# verdict at render time (nominating -> voting -> closed [-> runoff -> closed]
# [-> tie] -> decided) and the booleans restate it for the common checks, so
# clients never re-derive the windows from the timestamps. `pending_ties`
# (the categories still awaiting a decision: the runoff's ballot while it is
# open, then whatever it left tied for an admin) and `runoff_ties` (the
# runoff's original ballot) embed each tied game (the GameSummaryResource
# shape) so a runoff panel or an admin prompt can render the choice without a
# lookup per game.
class VotingRoundResource
  include BaseResource

  attributes :round_number, :month_year, :voting_opens_at, :voting_closes_at, :closed_at,
             :runoff_opens_at, :runoff_closes_at, :runoff_closed_at, :decided_at

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

  attribute :runoff_open do |round|
    round.runoff_open?
  end

  attribute :runoff_ended do |round|
    round.runoff_ended?
  end

  attribute :pending_ties do |round|
    embed_games(round.pending_ties)
  end

  attribute :runoff_ties do |round|
    embed_games(round.runoff_ties)
  end

  private

  # { category => [game_id, ...] } with each id swapped for its game.
  def embed_games(ties)
    ids = ties.values.flatten
    games = ids.empty? ? {} : GamedbGame.where(game_id: ids).preload(:images).index_by(&:game_id)
    ties.transform_values do |game_ids|
      game_ids.filter_map { |id| games[id] }.map { |game| GameSummaryResource.new(game).serializable_hash }
    end
  end
end
