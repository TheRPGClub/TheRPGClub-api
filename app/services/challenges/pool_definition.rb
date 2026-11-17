# frozen_string_literal: true

module Challenges
  # Which games are in a Pool (GLOSSARY.md, "Pool"): a game is in it if it
  # belongs to a chosen GameDB franchise or collection and is not excluded,
  # or if it is included by hand. It is resolved against the GameDB whenever
  # it is read, so a game added to a franchise later joins the Pool.
  #
  #   definition = PoolDefinition.parse("franchise_ids" => [ 1 ], "excluded_game_ids" => [ 9 ])
  #   definition.games # => GamedbGame relation
  PoolDefinition = Data.define(:franchise_ids, :collection_ids, :included_game_ids, :excluded_game_ids) do
    def self.empty = new(franchise_ids: [], collection_ids: [], included_game_ids: [], excluded_game_ids: [])

    # A Challenge's stored definition.
    def self.of(challenge)
      games = challenge.pool_games.to_a
      new(
        franchise_ids: challenge.pool_franchises.map(&:franchise_id).sort,
        collection_ids: challenge.pool_collections.map(&:collection_id).sort,
        included_game_ids: games.select { |row| row.inclusion == "include" }.map(&:game_id).sort,
        excluded_game_ids: games.select { |row| row.inclusion == "exclude" }.map(&:game_id).sort
      )
    end

    # `input`'s id lists replacing those of `base` (only the keys it has).
    # Raises Challenges::Invalid for a list that is not of ids.
    def self.parse(input, base: empty)
      raise Invalid, "pool must be an object" unless input.is_a?(Hash)

      base.with(**members.filter_map do |key|
        next unless input.key?(key.to_s)

        [ key, ids(input[key.to_s], key) ]
      end.to_h)
    end

    def self.ids(value, key)
      raise Invalid, "pool #{key} must be a list of ids" unless value.is_a?(Array)

      value.map do |id|
        Integer(id.to_s, 10).tap { |int| raise ArgumentError unless int.positive? }
      rescue ArgumentError
        raise Invalid, "pool #{key} must be a list of ids"
      end.uniq.sort
    end
    private_class_method :ids

    def empty? = franchise_ids.empty? && collection_ids.empty? && included_game_ids.empty?

    # The games in the Pool, as a GamedbGame relation.
    def games
      sourced = GamedbGame.where(game_id: GamedbGameFranchise.where(franchise_id: franchise_ids).select(:game_id))
        .or(GamedbGame.where(collection_id: collection_ids))
        .where.not(game_id: excluded_game_ids)
      sourced.or(GamedbGame.where(game_id: included_game_ids))
    end

    # Why this is not a Pool the GameDB can resolve (empty when it is).
    def errors
      messages = []
      messages << "A Pool needs at least one franchise, collection or included game" if empty?
      unknown(GamedbFranchise, franchise_ids).then { |ids| messages << "Unknown franchise ids: #{ids.join(', ')}" if ids.any? }
      unknown(GamedbCollection, collection_ids).then { |ids| messages << "Unknown collection ids: #{ids.join(', ')}" if ids.any? }
      unknown(GamedbGame, included_game_ids | excluded_game_ids).then do |ids|
        messages << "Unknown game ids: #{ids.join(', ')}" if ids.any?
      end
      both = included_game_ids & excluded_game_ids
      messages << "Games both included and excluded: #{both.join(', ')}" if both.any?
      messages
    end

    private

    def unknown(model, ids)
      return [] if ids.empty?

      ids - model.where(model.primary_key => ids).pluck(model.primary_key)
    end
  end
end
