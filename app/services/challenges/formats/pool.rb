# frozen_string_literal: true

module Challenges
  module Formats
    # The Pool Challenge Format (GLOSSARY.md, "Pool"): any game from a set the
    # Host chose counts. Its settings are the Pool's definition
    # (Challenges::PoolDefinition) and its target: a number of Cleared games
    # (at least 1), or "all" for every game in the Pool (`pool_target` null).
    #
    # Request and response object:
    #   { franchise_ids, collection_ids, included_game_ids, excluded_game_ids,
    #     target: 5 | "all" }
    # A response names each franchise, collection and game, and the show adds
    # `game_count`.
    module Pool
      KEY = "pool"
      ALL = "all"

      Settings = Data.define(:definition, :target)

      def self.load(challenge)
        Settings.new(definition: PoolDefinition.of(challenge), target: challenge.pool_target)
      end

      def self.parse(input, base: nil)
        raise Invalid, "pool is required for a Pool Challenge" unless input.is_a?(Hash) || base
        raise Invalid, "pool must be an object" unless input.nil? || input.is_a?(Hash)

        input ||= {}
        definition = PoolDefinition.parse(input, base: base&.definition || PoolDefinition.empty)
        target = input.key?("target") ? parse_target(input["target"]) : base&.target
        raise Invalid, "pool target is required: a number of games or \"all\"" if base.nil? && !input.key?("target")

        Settings.new(definition: definition, target: target)
      end

      def self.parse_target(value)
        return nil if value == ALL

        target = Integer(value.to_s, 10)
        raise ArgumentError if target < 1

        target
      rescue ArgumentError
        raise Invalid, "pool target must be a whole number of games, at least 1, or \"all\""
      end
      private_class_method :parse_target

      def self.errors(settings, _challenge = nil) = settings.definition.errors

      def self.apply!(challenge, settings)
        definition = settings.definition
        challenge.update_columns(pool_target: settings.target)
        replace(ChallengePoolFranchise, challenge, :franchise_id, definition.franchise_ids)
        replace(ChallengePoolCollection, challenge, :collection_id, definition.collection_ids)
        ChallengePoolGame.where(challenge_id: challenge.id).delete_all
        rows = definition.included_game_ids.map { |id| { game_id: id, inclusion: "include" } } +
          definition.excluded_game_ids.map { |id| { game_id: id, inclusion: "exclude" } }
        ChallengePoolGame.insert_all!(rows.map { |row| row.merge(challenge_id: challenge.id) }) if rows.any?
      end

      def self.replace(model, challenge, column, ids)
        model.where(challenge_id: challenge.id).delete_all
        model.insert_all!(ids.map { |id| { challenge_id: challenge.id, column => id } }) if ids.any?
      end
      private_class_method :replace

      def self.rules(settings) = settings.to_h

      # Run progress (Challenges::Progress): every game in the Pool the
      # member played inside the Run's window counts, In Progress or Cleared.
      def self.count(run, plays)
        game_ids = plays.game_ids
        return [] if game_ids.empty?

        load(run.challenge).definition.games.where(game_id: game_ids).order(:game_id).pluck(:game_id)
          .map { |game_id| plays.counted(game_id) }
      end

      # The Run is Finished when its Cleared games reach the target: the
      # Challenge's number, or every game in the Pool now.
      def self.summary(run, entries)
        cleared = entries.count { |entry| entry.state == "cleared" }
        target = run.challenge.pool_target || run.challenge.pool_game_count
        Progress::Summary.new(in_progress: entries.count { |entry| entry.state == "in_progress" }, cleared: cleared,
          target: target, goal_reached: target.positive? && cleared >= target)
      end

      # A Pool Run needs nothing of its own to start, and tells the member
      # nothing more (Challenges::Runs.start!).
      def self.run_attributes(_challenge, _user_id, **) = {}

      def self.notices(_run) = []

      def self.as_json(challenge, settings, detail: false)
        definition = settings.definition
        names = names_for(challenge)
        json = {
          target: settings.target || ALL,
          franchises: definition.franchise_ids.map { |id| { franchise_id: id, name: names[:franchises][id] } },
          collections: definition.collection_ids.map { |id| { collection_id: id, name: names[:collections][id] } },
          included_games: definition.included_game_ids.map { |id| { game_id: id, title: names[:games][id] } },
          excluded_games: definition.excluded_game_ids.map { |id| { game_id: id, title: names[:games][id] } }
        }
        json[:game_count] = challenge.pool_game_count if detail
        json
      end

      # Names of the chosen franchises, collections and games, from the
      # Challenge's preloaded rows.
      def self.names_for(challenge)
        {
          franchises: challenge.pool_franchises.to_h { |row| [ row.franchise_id, row.franchise.name ] },
          collections: challenge.pool_collections.to_h { |row| [ row.collection_id, row.collection.name ] },
          games: challenge.pool_games.to_h { |row| [ row.game_id, row.game.title ] }
        }
      end
      private_class_method :names_for
    end
  end
end
