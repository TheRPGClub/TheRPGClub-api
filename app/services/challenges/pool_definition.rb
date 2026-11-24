# frozen_string_literal: true

module Challenges
  # Which games are in a Pool (GLOSSARY.md, "Pool", "Core Game", "Optional
  # Game"; docs/adr/0014), resolved against the GameDB whenever it is read:
  #
  #   Core      the games a person made Core (`core_game_ids`)
  #   Optional  the games of the live sources (PoolSources::ALL: the
  #             linked Game List and the chosen Franchises and Series),
  #             less Add-ons (games with a parent
  #             game), plus the games a person made Optional, less the
  #             excluded and the Core games
  #
  # So a source only ever adds Optional Games, an Add-on joins only when
  # picked by hand, and a game the Host removed stays out though its source
  # still has it.
  #
  #   definition = PoolDefinition.parse("franchise_ids" => [ 1 ], "core_game_ids" => [ 9 ])
  #   definition.optional_games # => GamedbGame relation
  #
  # `game_list_ids` (the linked list, at most one) is stored on the
  # Challenge and set only on create (Challenges::ListLink), so a request
  # never parses it.
  PoolDefinition = Data.define(:franchise_ids, :collection_ids, :core_game_ids, :optional_game_ids,
    :excluded_game_ids, :game_list_ids) do
    def self.empty = new(**members.index_with { [] })

    # The lists a request may give.
    def self.parsed_members = members - [ :game_list_ids ]

    # A Challenge's stored definition.
    def self.of(challenge)
      games = challenge.pool_games.to_a
      new(
        franchise_ids: challenge.pool_franchises.map(&:franchise_id).sort,
        collection_ids: challenge.pool_collections.map(&:collection_id).sort,
        game_list_ids: [ challenge.pool_game_list_id ].compact,
        **PoolSources::HAND_LISTS.to_h { |inclusion, key| [ key, games.select { |row| row.inclusion == inclusion }.map(&:game_id).sort ] }
      )
    end

    # `input`'s id lists replacing those of `base` (only the keys it has).
    # Raises Challenges::Invalid for a list that is not of ids.
    def self.parse(input, base: empty)
      raise Invalid, "pool must be an object" unless input.is_a?(Hash)

      base.with(**parsed_members.filter_map do |key|
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

    # The source kinds and which games each holds, so they resolve alike.
    def sources = PoolSources::ALL.map { |source| [ source, public_send(source.member) ] }.reject { |_, ids| ids.empty? }

    # Games of the chosen sources, Add-ons included (nil without sources).
    def sourced_games = sources.map { |source, ids| GamedbGame.where(game_id: source.game_ids(ids)) }.reduce(:or)

    def core_games = GamedbGame.where(game_id: core_game_ids)

    def optional_games
      hand = GamedbGame.where(game_id: optional_game_ids)
      sourced = sourced_games
      games = sourced ? sourced.where(parent_igdb_id: nil).or(hand) : hand
      games.where.not(game_id: excluded_game_ids + core_game_ids)
    end

    # Every game in the Pool, Core and Optional, as a GamedbGame relation.
    def games = GamedbGame.where(game_id: core_games.select(:game_id)).or(GamedbGame.where(game_id: optional_games.select(:game_id)))

    # Where each of the Optional Games `game_ids` comes from and when it
    # joined the Pool: `{ game_id => { source:, joined_at: } }`. A game a
    # person made Optional is "hand", joined at `hand_added_at[game_id]`;
    # otherwise its first source in PoolSources::ALL names it, and it joined
    # when the earliest of its sources took it in (nil when a source does
    # not know, which counts as long ago). A hand pick joined at the
    # earliest time known: a source that does not know can't make a game
    # the Host just picked old.
    def optional_origins(game_ids, hand_added_at: {})
      joins = Hash.new { |hash, key| hash[key] = [] }
      sources.each do |source, ids|
        source.joins(ids, game_ids).each { |game_id, joined_at| joins[game_id] << [ source.key, joined_at ] }
      end
      game_ids.index_with do |game_id|
        found = joins[game_id]
        hand = optional_game_ids.include?(game_id)
        found.unshift([ PoolSources::HAND, hand_added_at[game_id] ]) if hand
        times = found.map(&:last)
        joined = hand || times.exclude?(nil) ? times.compact.min : nil
        { source: found.first&.first, joined_at: joined }
      end
    end

    # Why this is not a Pool the GameDB can resolve (empty when it is).
    def errors
      messages = []
      sources.each do |source, ids|
        unknown(source.model, ids).then { |missing| messages << "Unknown #{source.label} ids: #{missing.join(', ')}" if missing.any? }
      end
      unknown(GamedbGame, PoolSources::HAND_LISTS.values.flat_map { |key| public_send(key) }.uniq).then do |ids|
        messages << "Unknown game ids: #{ids.join(', ')}" if ids.any?
      end
      twice = PoolSources::HAND_LISTS.values.combination(2).flat_map { |one, other| public_send(one) & public_send(other) }.uniq.sort
      messages << "Games in more than one of core, optional and excluded: #{twice.join(', ')}" if twice.any?
      messages
    end

    private

    def unknown(model, ids)
      return [] if ids.empty?

      ids - model.where(model.primary_key => ids).pluck(model.primary_key)
    end
  end
end
