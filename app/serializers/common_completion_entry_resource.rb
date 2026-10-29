# frozen_string_literal: true

# A row of CompletionsController#common: a game both members completed, the
# latest completion date across both, and each member's side (their latest
# CompletionEntry for the game plus how many times they completed it). Built
# from Completions::Common::Row values, not model records.
class CommonCompletionEntryResource
  include BaseResource

  attributes :gamedb_game_id, :latest_shared_date

  one :game, resource: GameSummaryResource

  attribute :left do |row|
    { latest: CompletionEntryResource.new(row.left.latest).serializable_hash, count: row.left.count }
  end

  attribute :right do |row|
    { latest: CompletionEntryResource.new(row.right.latest).serializable_hash, count: row.right.count }
  end
end
