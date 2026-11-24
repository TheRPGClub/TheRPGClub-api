# frozen_string_literal: true

module Challenges
  module Formats
    # The Pool Challenge Format (GLOSSARY.md, "Pool"; docs/adr/0014): a Run
    # Finishes by Clearing every Core Game plus `optional_target` Optional
    # Games (0 by default). Its settings are the Pool's definition
    # (Challenges::PoolDefinition) and that target, stored as
    # `pool_optional_target`.
    #
    # Request object (on edit, only the keys given change):
    #   { franchise_ids, collection_ids, core_game_ids, optional_game_ids,
    #     excluded_game_ids, optional_target }
    #
    # None of it is a locked rule: the Host edits the Pool's games, sources
    # and target once Runs exist. After such an edit the Challenge's Runs are
    # brought up to date (a Run that now meets the goal Finishes), and adding
    # Core Games or raising the target DMs the members with an Active Run
    # (Challenges::DirectMessages.pool_goal_changed!).
    module Pool
      KEY = "pool"
      # An Optional Game is new this long after it joined the Pool.
      NEW_FOR = 14.days

      Settings = Data.define(:definition, :optional_target)

      def self.load(challenge)
        Settings.new(definition: PoolDefinition.of(challenge), optional_target: challenge.pool_optional_target)
      end

      def self.parse(input, base: nil)
        raise Invalid, "pool is required for a Pool Challenge" unless input.is_a?(Hash) || base
        raise Invalid, "pool must be an object" unless input.nil? || input.is_a?(Hash)

        input ||= {}
        definition = PoolDefinition.parse(input, base: base&.definition || PoolDefinition.empty)
        target = input.key?("optional_target") ? parse_target(input["optional_target"]) : base&.optional_target || 0
        Settings.new(definition: definition, optional_target: target)
      end

      def self.parse_target(value)
        target = Integer(value.to_s, 10)
        raise ArgumentError if target.negative?

        target
      rescue ArgumentError
        raise Invalid, "pool optional_target must be a whole number of games, 0 or more"
      end
      private_class_method :parse_target

      # A Pool needs a goal (a Core Game, or a target of at least 1), and
      # the target can't ask for more Optional Games than the Pool has now.
      # An edit of a Pool already short of its target (a source shrank
      # since: `base`, the stored settings) still saves when it leaves the
      # Pool no shorter: the target not raised and no Optional Game fewer.
      # The Pool then shows its goal as it is.
      def self.errors(settings, _challenge = nil, base: nil)
        definition = settings.definition
        messages = definition.errors
        return messages if messages.any?

        target = settings.optional_target
        if definition.core_game_ids.empty? && target.zero?
          messages << "A Pool needs at least one Core Game or an Optional target of at least 1"
        end
        if target.positive? && (count = definition.optional_games.count) < target && !no_shorter?(settings, base, count)
          messages << "The Optional target (#{target}) is more than the #{count} Optional Games in the Pool"
        end
        messages
      end

      def self.no_shorter?(settings, base, count)
        return false unless base
        return true if settings == base

        settings.optional_target <= base.optional_target && count >= base.definition.optional_games.count
      end
      private_class_method :no_shorter?

      # Writes the settings. A game kept Core or Optional keeps the time it
      # joined; a game new to the hand-picked lists joined now (when the
      # Challenge was created, on create).
      def self.apply!(challenge, settings)
        definition = settings.definition
        challenge.update_columns(pool_optional_target: settings.optional_target)
        replace(ChallengePoolFranchise, challenge, :franchise_id, definition.franchise_ids)
        replace(ChallengePoolCollection, challenge, :collection_id, definition.collection_ids)

        kept = ChallengePoolGame.where(challenge_id: challenge.id, inclusion: %w[core optional]).pluck(:game_id, :added_at).to_h
        now = challenge.previously_new_record? ? challenge.created_at : Time.current
        ChallengePoolGame.where(challenge_id: challenge.id).delete_all
        rows = PoolSources::HAND_LISTS.flat_map do |inclusion, key|
          definition.public_send(key).map do |id|
            { challenge_id: challenge.id, game_id: id, inclusion: inclusion,
              added_at: (inclusion == "exclude" ? now : kept[id] || now) }
          end
        end
        ChallengePoolGame.insert_all!(rows) if rows.any?
        challenge.pool_games.reset
        # A list notice is about a Core Game; one no longer Core needs none.
        ChallengePoolListNotice.where(challenge_id: challenge.id).where.not(game_id: definition.core_game_ids).delete_all
      end

      def self.replace(model, challenge, column, ids)
        model.where(challenge_id: challenge.id).delete_all
        model.insert_all!(ids.map { |id| { challenge_id: challenge.id, column => id } }) if ids.any?
      end
      private_class_method :replace

      # Nothing of a Pool is locked once Runs exist (docs/adr/0014).
      def self.rules(_settings) = nil

      # After an edit of a Challenge that has Runs (Challenges::Form): brings
      # its Runs up to date, then tells the members with an Active Run when
      # their goal grew.
      def self.edited!(challenge, before, after)
        return if before == after

        user_ids = challenge.runs.where(status: %w[active finished]).distinct.pluck(:user_id)
        user_ids.each { |user_id| Challenges.refresh_runs!(user_id) }

        added = after.definition.core_game_ids - before.definition.core_game_ids
        raised = after.optional_target > before.optional_target
        return if added.empty? && !raised

        DirectMessages.pool_goal_changed!(challenge, added_core_game_ids: added,
          optional_target: (raised ? { from: before.optional_target, to: after.optional_target } : nil))
      end

      # Run progress (Challenges::Progress): every game in the Pool the
      # member played inside the Run's window counts, In Progress or Cleared.
      def self.count(run, plays)
        game_ids = plays.game_ids
        return [] if game_ids.empty?

        load(run.challenge).definition.games.where(game_id: game_ids).order(:game_id).pluck(:game_id)
          .map { |game_id| plays.counted(game_id) }
      end

      # The Run is Finished when every Core Game is Cleared and its Cleared
      # Optional Games reach the target. `target` is the games that takes;
      # Optional Games Cleared past it still count in `cleared`.
      def self.summary(run, entries)
        challenge = run.challenge
        core_ids = challenge.pool_games.select { |row| row.inclusion == "core" }.to_set(&:game_id)
        cleared = entries.select { |entry| entry.state == "cleared" }
        core_cleared = cleared.count { |entry| core_ids.include?(entry.game_id) }
        optional_cleared = cleared.size - core_cleared
        optional_target = challenge.pool_optional_target
        target = core_ids.size + optional_target
        Progress::Summary.new(
          in_progress: entries.count { |entry| entry.state == "in_progress" }, cleared: cleared.size, target: target,
          goal_reached: target.positive? && core_cleared == core_ids.size && optional_cleared >= optional_target,
          core: { cleared: core_cleared, total: core_ids.size },
          optional: { cleared: optional_cleared, target: optional_target }
        )
      end

      # A Pool Run needs nothing of its own to start, and tells the member
      # nothing more (Challenges::Runs.start!).
      def self.run_attributes(_challenge, _user_id, **) = {}

      def self.notices(_run) = []

      # The Pool as the API serves it. Lists carry the sources, the Core and
      # excluded games (from the Challenge's preloaded rows); the show
      # (`detail`) adds the Optional Games, resolved live, and the counts.
      # `game_list` is the linked list, `visible` and `can_add` for `viewer`
      # (a Challenges::Actor; without one, as for a member who owns no list).
      def self.as_json(challenge, settings, detail: false, now: Time.current, viewer: nil)
        definition = settings.definition
        rows = challenge.pool_games.to_a
        core = rows.select { |row| row.inclusion == "core" }.map(&:game)
        optional = optional_json(challenge, definition, rows, now) if detail
        {
          optional_target: settings.optional_target,
          game_list: game_list_json(challenge, viewer),
          franchises: challenge.pool_franchises.map { |row| { franchise_id: row.franchise_id, name: row.franchise.name } }
            .sort_by { |source| source[:franchise_id] },
          collections: challenge.pool_collections.map { |row| { collection_id: row.collection_id, name: row.collection.name } }
            .sort_by { |source| source[:collection_id] },
          core_games: sorted(core).map { |game| game_json(game) },
          optional_games: optional,
          excluded_games: rows.select { |row| row.inclusion == "exclude" }.map(&:game).sort_by { |game| [ game.title.to_s, game.game_id ] }
            .map { |game| { game_id: game.game_id, title: game.title } },
          core_count: core.size,
          optional_count: optional&.size,
          game_count: optional && (core.size + optional.size)
        }
      end

      def self.game_list_json(challenge, viewer)
        list = challenge.pool_game_list
        return nil unless list

        { id: list.id, name: list.name, visible: !list.private? || list.owned_by?(viewer&.user_id),
          can_add: viewer ? viewer.can_add_to_list?(challenge, list) : false }
      end
      private_class_method :game_list_json

      def self.optional_json(challenge, definition, rows, now)
        games = definition.optional_games.preload(:images)
          .order(Arel.sql("gamedb_games.initial_release_date ASC NULLS LAST, gamedb_games.title ASC")).to_a
        hand_added_at = rows.select { |row| row.inclusion == "optional" }.to_h { |row| [ row.game_id, row.added_at ] }
        origins = definition.optional_origins(games.map(&:game_id), hand_added_at: hand_added_at)
        games.map do |game|
          origin = origins.fetch(game.game_id)
          joined = origin[:joined_at]
          game_json(game).merge(source: origin[:source],
            new: joined.present? && joined > challenge.created_at && joined > now - NEW_FOR)
        end
      end
      private_class_method :optional_json

      def self.sorted(games)
        games.sort_by do |game|
          date = game.initial_release_date
          [ date ? 0 : 1, date || Time.zone.at(0), game.title.to_s, game.game_id ]
        end
      end
      private_class_method :sorted

      def self.game_json(game) = { game_id: game.game_id, title: game.title, cover_url: game.cover_url }
      private_class_method :game_json
    end
  end
end
