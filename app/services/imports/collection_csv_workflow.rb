# frozen_string_literal: true

module Imports
  # The server-side collection CSV import loop (#290), ported from the bot's
  # renderNextCsvImportItem / applyCsvImportSelection. Controllers check the
  # owner first; this class does no authorization and no transaction
  # handling (wrap calls in TestModeRollback).
  #
  #   workflow = Imports::CollectionCsvWorkflow.new(import)
  #   review = workflow.advance        # => Imports::Review
  #   workflow.apply(item, game, reason: "manual_remap")
  #   workflow.skip(item)
  #   workflow.remap(item, "New title")  # => [Candidate]
  #
  # #advance walks pending items in row_index order, updating current_index:
  # - raw_gamedb_id: apply that game (csv_gamedb_id), or fail invalid_row if
  #   it is not in GameDB.
  # - raw_igdb_id: resolve it with IgdbGameResolver and apply (csv_igdb_id),
  #   or fail invalid_row.
  # - otherwise load the stored candidates, or find and store them
  #   (CandidateFinder#find on raw_title) unless a remap found none
  #   (no_candidate: the list stays empty); a single candidate that
  #   TitleNormalizer.exact_match?es raw_title is applied (auto_match).
  # It returns the first item that needs a human. When no pending item is
  # left the import is marked completed and `item` is nil; `item` is also nil
  # (with the import still active) after MAX_AUTO_APPLIES rows were resolved
  # in one call, so a request stays short; call it again to continue.
  #
  # Applying re-resolves the platform, ownership and note from the raw row
  # (an unresolvable platform imports without one: platform_unresolved) and
  # records the CollectionApplier outcome on the item.
  class CollectionCsvWorkflow
    MAX_AUTO_APPLIES = 25
    PLATFORM_WARNING = "Platform not recognized; imported without platform."

    def initialize(import, platform_resolver: PlatformResolver.new, candidate_finder: CandidateFinder.new,
      igdb_resolver: IgdbGameResolver.new)
      @import = import
      @platform_resolver = platform_resolver
      @candidate_finder = candidate_finder
      @igdb_resolver = igdb_resolver
    end

    def advance
      MAX_AUTO_APPLIES.times do
        item = @import.items.where(status: "pending").order(:row_index).first
        unless item
          @import.update!(status: "completed")
          return Review.none
        end

        @import.update!(current_index: item.row_index)
        review = process(item)
        return review if review
      end
      Review.none
    end

    def apply(item, game, reason:)
      platform_id = item.raw_platform.present? ? @platform_resolver.resolve(item.raw_platform) : nil
      unresolved = item.raw_platform.present? && platform_id.nil?
      ownership_type = CollectionApplier.normalize_ownership(item.raw_ownership_type) || CollectionApplier::DEFAULT_OWNERSHIP

      result = CollectionApplier.new(user_id: @import.user_id).apply(
        game_id: game.game_id, platform_id: platform_id, ownership_type: ownership_type,
        note: item.raw_note, platform_unresolved: unresolved
      )

      item.update!(
        status: result.status,
        result_reason: result.reason || reason,
        error_text: result.error || (result.added? && unresolved ? PLATFORM_WARNING : nil),
        match_confidence: reason == "auto_match" ? "exact" : "manual",
        gamedb_game_id: game.game_id,
        collection_entry_id: result.entry&.entry_id,
        platform_id: platform_id,
        ownership_type: ownership_type,
        note: item.raw_note
      )
      item
    end

    def skip(item)
      item.update!(status: "skipped", result_reason: "manual_skip")
      item
    end

    # Re-searches GameDB for `title` and stores the candidates (reason
    # no_candidate when there are none). The next #advance auto-applies a
    # single exact match against the row's raw_title, as the bot does.
    def remap(item, title)
      candidates = @candidate_finder.find(title)
      item.update!(
        match_candidate_json: candidates.any? ? CandidateFinder.dump(candidates) : nil,
        match_confidence: CandidateFinder.confidence(title, candidates),
        result_reason: candidates.any? ? nil : "no_candidate",
        error_text: nil
      )
      candidates
    end

    private

    # nil when the item was resolved automatically, otherwise its Review.
    def process(item)
      return apply_gamedb_id(item) if item.raw_gamedb_id.present?
      return apply_igdb_id(item) if item.raw_igdb_id.present?

      candidates = CandidateFinder.load(item.match_candidate_json)
      if candidates.empty? && !remapped_without_candidates?(item)
        candidates = @candidate_finder.find(item.raw_title)
        item.update!(
          match_candidate_json: candidates.any? ? CandidateFinder.dump(candidates) : nil,
          match_confidence: CandidateFinder.confidence(item.raw_title, candidates)
        )
      end

      game = exact_single_match(item, candidates)
      if game
        apply(item, game, reason: "auto_match")
        return
      end

      Review.for(item, candidates)
    end

    # A remap that found nothing leaves result_reason no_candidate; the row
    # keeps its empty list rather than falling back to the raw title.
    def remapped_without_candidates?(item)
      item.result_reason == "no_candidate"
    end

    def exact_single_match(item, candidates)
      return unless candidates.one? && TitleNormalizer.exact_match?(item.raw_title, candidates.first.title)

      GamedbGame.find_by(game_id: candidates.first.game_id)
    end

    def apply_gamedb_id(item)
      game = GamedbGame.find_by(game_id: item.raw_gamedb_id)
      return fail_row(item, "GameDB id #{item.raw_gamedb_id} was not found.") unless game

      apply(item, game, reason: "csv_gamedb_id")
      nil
    end

    def apply_igdb_id(item)
      result = @igdb_resolver.resolve(item.raw_igdb_id)
      return fail_row(item, "IGDB id #{item.raw_igdb_id} could not be imported (#{result.error}).") unless result.ok?

      apply(item, result.game, reason: "csv_igdb_id")
      nil
    end

    def fail_row(item, message)
      item.update!(status: "failed", result_reason: "invalid_row", error_text: message)
      nil
    end
  end
end
