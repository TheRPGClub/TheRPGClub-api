# frozen_string_literal: true

module Challenges
  # The live sources a Pool draws Optional Games from (docs/adr/0014), in the
  # order that names a game's `source` when several hold it. Each knows
  #
  #   member       the Challenges::PoolDefinition list of its ids
  #   model        the GameDB model those ids are of (unknown ids are refused)
  #   game_ids     a game_id subquery of the games of `ids`
  #   joins        [game_id, joined_at] for those of `game_ids` it holds;
  #                joined_at nil when it is not known (counts as long ago)
  #   challenge_sql  SQL of (challenge_id, game_id) for the Challenges
  #                `:ids`, for reading many Pools at once (PoolCovers)
  #
  # A new source (a linked Game List) is one more entry here plus its list
  # in PoolDefinition.
  module PoolSources
    # A game a person made Optional by hand.
    HAND = "hand"
    # The lists a person picks by hand, by the `challenge_pool_games.inclusion`
    # each is stored as.
    HAND_LISTS = { "core" => :core_game_ids, "optional" => :optional_game_ids, "exclude" => :excluded_game_ids }.freeze

    Source = Data.define(:key, :label, :member, :model, :game_ids_of, :joins_of, :challenge_sql) do
      def game_ids(ids) = game_ids_of.call(ids)

      def joins(ids, game_ids) = joins_of.call(ids, game_ids)
    end

    FRANCHISE = Source.new(
      key: "franchise", label: "franchise", member: :franchise_ids, model: GamedbFranchise,
      game_ids_of: ->(ids) { GamedbGameFranchise.where(franchise_id: ids).select(:game_id) },
      joins_of: ->(ids, game_ids) { GamedbGameFranchise.where(franchise_id: ids, game_id: game_ids).pluck(:game_id, :created_at) },
      challenge_sql: <<~SQL.squish
        SELECT pf.challenge_id, gf.game_id FROM challenge_pool_franchises pf
          JOIN gamedb_game_franchises gf ON gf.franchise_id = pf.franchise_id
          WHERE pf.challenge_id IN (:ids)
      SQL
    )

    # IGDB collections, which members know as Series. A game's Series is a
    # column, with no time it joined.
    SERIES = Source.new(
      key: "series", label: "collection", member: :collection_ids, model: GamedbCollection,
      game_ids_of: ->(ids) { GamedbGame.where(collection_id: ids).select(:game_id) },
      joins_of: ->(ids, game_ids) { GamedbGame.where(collection_id: ids, game_id: game_ids).pluck(:game_id).map { |id| [ id, nil ] } },
      challenge_sql: <<~SQL.squish
        SELECT pc.challenge_id, g.game_id FROM challenge_pool_collections pc
          JOIN gamedb_games g ON g.collection_id = pc.collection_id
          WHERE pc.challenge_id IN (:ids)
      SQL
    )

    ALL = [ FRANCHISE, SERIES ].freeze
  end
end
