# frozen_string_literal: true

module Playtime
  # The one place Playtime is worked out (spec api#457, ADR 0015). A member's
  # Playtime for a game is the plain sum of:
  #
  # - each Provider figure: `user_achievement_set_progress.playtime_minutes`
  #   on a synced set mapped to the game (`achievement_sets.game_id`); an
  #   unmapped set counts for nothing.
  # - each Manual Playtime entry (UserGameManualPlaytime), one per platform.
  #
  # A Provider figure is shown but not counted when the member's Manual entry
  # on the same resolved platform `keeps_over_provider` that Provider ("keep
  # mine"). Otherwise a Manual entry and a Provider set on the same resolved
  # platform are a mismatch for the member to settle, unless the entry's
  # `mismatch_acknowledged_provider` is that Provider ("keep both": both
  # count, no mismatch). A set's `platform_label`
  # is resolved with Imports::PlatformResolver; a label that doesn't resolve
  # stays raw and never takes part in a mismatch.
  #
  # Batches: one Ledger covers every pair of `user_ids` x `game_ids` in a
  # single query (plus one read of the platforms when any Provider row needs
  # resolving). Leave one side nil for "all": `user_ids: [id]` alone is every
  # game the member has Playtime on (profile totals), `game_ids: ids` alone is
  # every member with Playtime on those games (Franchise pages).
  #
  #   Playtime::Ledger.for_game(user_id:, game_id:)          # one GamePlaytime
  #   ledger = Playtime::Ledger.new(user_ids: [id], game_ids: shelf_ids)
  #   ledger.minutes_by_game(id)                              # { game_id => minutes }
  #   Playtime::Ledger.new(game_ids: franchise_ids).minutes_by_user(game_id)
  #
  # Each GamePlaytime carries the member's open Playthrough of the game, read
  # for the whole batch in one more query, and its time (`playthrough_minutes`).
  class Ledger
    ProviderSet = Struct.new(:achievement_set_id, :provider, :title, :platform_label, :platform_id, :minutes,
      :counted, keyword_init: true)
    ManualEntry = Struct.new(:id, :platform_id, :minutes, :note, :origin, :keeps_over_provider,
      :mismatch_acknowledged_provider, :created_at, :updated_at, keyword_init: true)
    Mismatch = Struct.new(:platform_id, :provider, :provider_minutes, :manual_playtime_id, :manual_minutes,
      keyword_init: true)

    # One member's Playtime for one game, with their open Playthrough of it
    # (a UserGamePlaythrough, or nil).
    class GamePlaytime
      attr_reader :user_id, :game_id, :provider_sets, :manual_entries, :mismatches, :open_playthrough

      def initialize(user_id:, game_id:, provider_sets: [], manual_entries: [], open_playthrough: nil)
        @user_id = user_id
        @game_id = game_id
        @open_playthrough = open_playthrough
        @manual_entries = manual_entries.sort_by { |entry| [ entry.platform_id ? 0 : 1, entry.platform_id.to_i ] }
        @provider_sets = provider_sets.sort_by { |set| [ set.provider, set.title.to_s, set.achievement_set_id ] }
        @mismatches = []
        apply_keeps
      end

      def total_minutes
        provider_sets.select(&:counted).sum(&:minutes) + manual_entries.sum(&:minutes)
      end

      def empty? = provider_sets.empty? && manual_entries.empty?

      # The open Playthrough's time (its manual total, or the Playtime gained
      # since it started); nil when none is open.
      def playthrough_minutes = open_playthrough&.minutes_at(total_minutes)

      # The Manual entry on `platform_id` (nil is Other), if any.
      def manual_entry_for(platform_id) = manual_entries.find { |entry| entry.platform_id == platform_id }

      private

      # Marks the Provider sets a Manual entry keeps over as not counted, and
      # collects a mismatch per (platform, Provider) left unsettled ("keep
      # both" settles one with both still counting).
      def apply_keeps
        manual_entries.each do |entry|
          next if entry.platform_id.nil?

          on_platform = provider_sets.select { |set| set.platform_id == entry.platform_id }
          on_platform.group_by(&:provider).each do |provider, sets|
            if provider == entry.keeps_over_provider
              sets.each { |set| set.counted = false }
            elsif provider != entry.mismatch_acknowledged_provider
              @mismatches << Mismatch.new(platform_id: entry.platform_id, provider: provider,
                provider_minutes: sets.sum(&:minutes), manual_playtime_id: entry.id, manual_minutes: entry.minutes)
            end
          end
        end
      end
    end

    def self.for_game(user_id:, game_id:, resolver: nil)
      new(user_ids: [ user_id ], game_ids: [ game_id ], resolver: resolver).for(user_id, game_id)
    end

    # The (user, game) pairs, among `user_ids` (all when nil), that have a
    # Provider figure: the launch seed skips these (ADR 0015).
    def self.provider_reported(user_ids: nil, game_ids: nil)
      scope = provider_scope(user_ids, game_ids).where("user_achievement_set_progress.playtime_minutes > 0")
      scope.distinct.pluck("user_achievement_set_progress.user_id", "achievement_sets.game_id").to_set
    end

    def self.provider_scope(user_ids, game_ids)
      scope = UserAchievementSetProgress.synced.where.not(playtime_minutes: nil)
        .joins(:achievement_set).where.not(achievement_sets: { game_id: nil })
      scope = scope.where(user_id: user_ids) if user_ids
      scope = scope.where(achievement_sets: { game_id: game_ids }) if game_ids
      scope
    end

    # `resolver` may be shared across Ledgers (it reads the platforms once).
    def initialize(user_ids: nil, game_ids: nil, resolver: nil)
      raise ArgumentError, "give user_ids, game_ids or both" if user_ids.nil? && game_ids.nil?

      @user_ids = user_ids&.map(&:to_s)
      @game_ids = game_ids&.map(&:to_i)
      @resolver = resolver
      @labels = {}
    end

    # The member's Playtime for the game; empty (0 minutes) when there is none.
    # Its open Playthrough comes along even then.
    def for(user_id, game_id)
      key = [ user_id.to_s, game_id.to_i ]
      by_pair.fetch(key) { GamePlaytime.new(user_id: key[0], game_id: key[1], open_playthrough: open_playthroughs[key]) }
    end

    def total_minutes(user_id, game_id) = self.for(user_id, game_id).total_minutes

    # Every GamePlaytime in the batch with any figure, in no set order.
    def each(&) = by_pair.each_value(&)
    include Enumerable

    # { game_id => minutes } for the member, games with any figure only.
    def minutes_by_game(user_id)
      user_id = user_id.to_s
      select { |playtime| playtime.user_id == user_id }.to_h { |playtime| [ playtime.game_id, playtime.total_minutes ] }
    end

    # { user_id => minutes } for the game, members with any figure only.
    def minutes_by_user(game_id)
      game_id = game_id.to_i
      select { |playtime| playtime.game_id == game_id }.to_h { |playtime| [ playtime.user_id, playtime.total_minutes ] }
    end

    private

    def by_pair
      @by_pair ||= begin
        providers = Hash.new { |hash, key| hash[key] = [] }
        manuals = Hash.new { |hash, key| hash[key] = [] }
        rows.each do |row|
          key = [ row["user_id"], row["game_id"] ]
          row["source"] == "provider" ? providers[key] << provider_set(row) : manuals[key] << manual_entry(row)
        end
        (providers.keys | manuals.keys).to_h do |key|
          [ key, GamePlaytime.new(user_id: key[0], game_id: key[1], provider_sets: providers[key],
            manual_entries: manuals[key], open_playthrough: open_playthroughs[key]) ]
        end
      end
    end

    # { [user_id, game_id] => UserGamePlaythrough } for the batch's open ones.
    def open_playthroughs
      @open_playthroughs ||= begin
        scope = UserGamePlaythrough.currently_open
        scope = scope.where(user_id: @user_ids) if @user_ids
        scope = scope.where(gamedb_game_id: @game_ids) if @game_ids
        @user_ids&.empty? || @game_ids&.empty? ? {} : scope.index_by { |row| [ row.user_id, row.gamedb_game_id ] }
      end
    end

    def provider_set(row)
      ProviderSet.new(achievement_set_id: row["achievement_set_id"], provider: row["provider"], title: row["title"],
        platform_label: row["platform_label"], platform_id: resolve(row["platform_label"]), minutes: row["minutes"],
        counted: true)
    end

    def manual_entry(row)
      ManualEntry.new(id: row["row_id"], platform_id: row["platform_id"], minutes: row["minutes"], note: row["note"],
        origin: row["origin"], keeps_over_provider: row["keeps_over_provider"],
        mismatch_acknowledged_provider: row["mismatch_acknowledged_provider"], created_at: row["created_at"],
        updated_at: row["updated_at"])
    end

    def resolve(label)
      return if label.blank?

      @labels.fetch(label) { @labels[label] = resolver.resolve(label) }
    end

    def resolver = @resolver ||= Imports::PlatformResolver.new

    # Both sources in one query, as rows of one shape.
    def rows
      return [] if @user_ids&.empty? || @game_ids&.empty?

      provider = self.class.provider_scope(@user_ids, @game_ids).select(<<~SQL.squish)
        'provider' AS source, user_achievement_set_progress.id AS row_id, user_achievement_set_progress.user_id,
        achievement_sets.game_id, achievement_sets.provider, achievement_sets.title, achievement_sets.platform_label,
        NULL::bigint AS platform_id, user_achievement_set_progress.playtime_minutes AS minutes,
        achievement_sets.id AS achievement_set_id, NULL::varchar AS note, NULL::varchar AS origin,
        NULL::varchar AS keeps_over_provider, NULL::varchar AS mismatch_acknowledged_provider,
        NULL::timestamp AS created_at, NULL::timestamp AS updated_at
      SQL
      manual = UserGameManualPlaytime.all
      manual = manual.where(user_id: @user_ids) if @user_ids
      manual = manual.where(gamedb_game_id: @game_ids) if @game_ids
      manual = manual.select(<<~SQL.squish)
        'manual' AS source, id AS row_id, user_id, gamedb_game_id AS game_id, NULL::varchar AS provider,
        NULL::varchar AS title, NULL::varchar AS platform_label, platform_id, minutes,
        NULL::bigint AS achievement_set_id, note, origin, keeps_over_provider, mismatch_acknowledged_provider,
        created_at, updated_at
      SQL

      result = ApplicationRecord.connection.select_all("(#{provider.to_sql}) UNION ALL (#{manual.to_sql})", "Playtime")
      types = result.column_types
      result.rows.map do |values|
        result.columns.each_with_index.to_h { |column, index| [ column, cast(types[column], values[index]) ] }
      end
    end

    def cast(type, value) = type ? type.deserialize(value) : value
  end
end
