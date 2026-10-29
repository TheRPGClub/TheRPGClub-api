# frozen_string_literal: true

module Imports
  # The server-side Steam collection import workflow (web-parity #289), ported
  # from the bot's collection-steam-import.command.ts so a signed-in member
  # can drive their own import from the web.
  #
  #   Imports::SteamWorkflow.item_rows(import_id, library[:games])  # rows for insert_all
  #
  #   workflow = Imports::SteamWorkflow.new(import)
  #   review = workflow.advance       # => Review(item:, candidates:, match_confidence:)
  #   workflow.apply(item, game_id)   # add to the collection (Digital, Steam), map the app
  #   workflow.skip(item)             # manual_skip, map the app as skipped
  #   workflow.remap(item, title)     # => [Candidate], stored on the item
  #
  # #advance pops pending items in row_index order. For each it computes the
  # candidates (#candidates_for), and when there is exactly one and its title
  # is a TitleNormalizer.exact_match? of the Steam name it applies it
  # (auto_match) and moves on. It stops at the first item that needs a human,
  # or completes the import when none remain. At most MAX_AUTO_APPLIES items
  # are auto-applied per call: when the cap is hit the Review has a nil item
  # while the import is still active, and the caller just advances again
  # (the same contract as Imports::CollectionCsvWorkflow).
  #
  # Authorization and TestModeRollback are the caller's job: the controllers
  # check the import's owner and wrap each request's writes.
  class SteamWorkflow
    MAX_AUTO_APPLIES = 25
    STEAM_PLATFORM = "steam"
    OWNERSHIP_TYPE = "Digital"
    HISTORICAL_LIMIT = 5

    Review = Data.define(:item, :candidates, :match_confidence)

    # Insert rows for a Steam::Client#owned_games library, row_index 1..n
    # (as the bot numbers them).
    def self.item_rows(import_id, games)
      games.each_with_index.map do |game, index|
        {
          import_id: import_id,
          row_index: index + 1,
          steam_app_id: game[:app_id],
          steam_app_name: game[:name],
          playtime_forever_min: game[:playtime_forever_minutes],
          playtime_windows_min: game[:playtime_windows_minutes],
          playtime_mac_min: game[:playtime_mac_minutes],
          playtime_linux_min: game[:playtime_linux_minutes],
          playtime_deck_min: game[:playtime_deck_minutes],
          last_played_at: game[:last_played_at],
          status: "pending"
        }
      end
    end

    def initialize(import, platform_resolver: PlatformResolver.new, candidate_finder: CandidateFinder.new)
      @import = import
      @platform_resolver = platform_resolver
      @candidate_finder = candidate_finder
    end

    def advance
      auto_applied = 0
      loop do
        item = @import.items.where(status: "pending").order(:row_index).first
        return complete unless item

        @import.update!(current_index: item.row_index) if @import.current_index != item.row_index
        candidates = candidates_for(item)
        unless auto_match?(item, candidates)
          return Review.new(item: item, candidates: candidates, match_confidence: item.match_confidence)
        end
        return Review.new(item: nil, candidates: [], match_confidence: nil) if auto_applied >= MAX_AUTO_APPLIES

        apply(item, candidates.first.game_id, reason: "auto_match")
        auto_applied += 1
      end
    end

    # The bot's applySteamImportSelection. `game_id` must be an existing
    # GameDB game. A manual pick (reason manual_remap) sets match_confidence
    # to manual.
    def apply(item, game_id, reason: "manual_remap")
      platform_id = steam_platform_id
      result = CollectionApplier.new(user_id: @import.user_id).apply(
        game_id: game_id, platform_id: platform_id, ownership_type: OWNERSHIP_TYPE,
        platform_unresolved: platform_id.nil?
      )
      attributes = { gamedb_game_id: game_id }
      attributes[:match_confidence] = "manual" if reason == "manual_remap"
      item.update!(attributes.merge(outcome(result, reason, platform_id)))
      upsert_map(item.steam_app_id, game_id, "mapped") unless result.failed?
      item
    end

    def skip(item)
      item.update!(status: "skipped", result_reason: "manual_skip", error_text: "Skipped by user.")
      upsert_map(item.steam_app_id, nil, "skipped")
      item
    end

    # Re-searches GameDB for `title` (already stripped and non-blank; the
    # controller rejects a blank one) and stores the candidates on the item,
    # or no_candidate when nothing matches. Nothing is applied: the next
    # #advance may auto-apply a single exact match.
    def remap(item, title)
      candidates = @candidate_finder.find(title)
      if candidates.empty?
        item.update!(match_candidate_json: nil, match_confidence: nil, result_reason: "no_candidate",
          error_text: "No candidates found for remap search \"#{title}\".")
      else
        item.update!(match_candidate_json: CandidateFinder.dump(candidates),
          match_confidence: CandidateFinder.confidence(title, candidates), result_reason: nil, error_text: nil)
      end
      candidates
    end

    private

    def complete
      @import.update!(status: "completed")
      Review.new(item: nil, candidates: [], match_confidence: nil)
    end

    def auto_match?(item, candidates)
      candidates.one? && TitleNormalizer.exact_match?(item.steam_app_name, candidates.first.title)
    end

    # Stored candidates, else: the Steam app map's game, else (unless the map
    # says skipped) a GameDB search; with several, the member's historically
    # mapped games are merged in. Persisted on the item.
    def candidates_for(item)
      stored = CandidateFinder.load(item.match_candidate_json)
      return stored if stored.any?

      map = RpgClubSteamAppGamedbMap.find_by(steam_app_id: item.steam_app_id)
      candidates = map&.status == "mapped" ? game_candidates([ map.gamedb_game_id ]) : []
      candidates = @candidate_finder.find(item.steam_app_name) if candidates.empty? && map&.status != "skipped"
      if candidates.many?
        candidates = (candidates + game_candidates(historical_game_ids)).uniq(&:game_id).first(CandidateFinder::MAX_CANDIDATES)
      end

      item.update!(
        match_candidate_json: candidates.any? ? CandidateFinder.dump(candidates) : nil,
        match_confidence: CandidateFinder.confidence(item.steam_app_name, candidates),
        result_reason: candidates.empty? && map&.status == "skipped" ? "skip_mapped" : nil
      )
      candidates
    end

    # Candidates for GameDB ids, in the given order (missing ids dropped).
    def game_candidates(game_ids)
      ids = game_ids.compact
      return [] if ids.empty?

      titles = GamedbGame.where(game_id: ids).pluck(:game_id, :title).to_h
      ids.filter_map { |id| titles[id] && Candidate.new(game_id: id, title: titles[id]) }
    end

    # The member's most recently mapped games (the bot's
    # getSteamAppHistoricalMappedGameIds, limit 5).
    def historical_game_ids
      RpgClubSteamAppGamedbMap
        .where(created_by: @import.user_id, status: "mapped")
        .where.not(gamedb_game_id: nil)
        .group(:gamedb_game_id)
        .order(Arel.sql("MAX(updated_at) DESC"), :gamedb_game_id)
        .limit(HISTORICAL_LIMIT)
        .pluck(:gamedb_game_id)
    end

    def outcome(result, reason, platform_id)
      if result.added?
        {
          status: "added", collection_entry_id: result.entry.entry_id, result_reason: result.reason || reason,
          error_text: platform_id ? nil : "Steam platform id not found; imported without platform."
        }
      elsif result.skipped?
        { status: "skipped", result_reason: "duplicate", error_text: "This game is already in the collection." }
      else
        { status: "failed", result_reason: "add_failed", error_text: result.error }
      end
    end

    def upsert_map(steam_app_id, game_id, status)
      map = RpgClubSteamAppGamedbMap.find_or_initialize_by(steam_app_id: steam_app_id)
      map.update!(gamedb_game_id: game_id, status: status, created_by: @import.user_id)
    end

    def steam_platform_id
      return @steam_platform_id if defined?(@steam_platform_id)

      @steam_platform_id = @platform_resolver.resolve_direct(STEAM_PLATFORM)
    end
  end
end
