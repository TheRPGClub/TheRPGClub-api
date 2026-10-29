# frozen_string_literal: true

module Imports
  # The Completionator import review loop, ported from the bot's
  # completionator-workflow.service.ts / completionator-handlers.service.ts.
  # One instance per request and import:
  #
  #   workflow = Imports::CompletionatorWorkflow.new(import)
  #   advance  = workflow.advance            # => AdvanceResult
  #   review   = workflow.match(item, game)  # => Review
  #   workflow.add_completion(item, attrs)   # => item (status "added")
  #   workflow.update_completion(item, %w[type date playtime]) # => item
  #   workflow.skip(item)                    # => item (status "skipped")
  #
  # #advance walks the pending items by row_index. For each it finds the
  # game (the item's gamedb_game_id, else CandidateFinder#find_with_fallback;
  # a single candidate auto-matches with no title check), then:
  #
  #   next_step            when
  #   "choose_game"        zero or several candidates
  #   "auto_added"         no existing completion and the form has a platform
  #                        (the bot's canAutoAddCompletion; the default date
  #                        choice is always csv-with-a-date or unknown)
  #   "add_completion"     no existing completion, no platform resolved
  #   "auto_skipped"       an existing completion and no diff
  #   "confirm_same"       an existing completion, both dates set and different
  #   "update_completion"  an existing completion with some diff
  #
  # Automatic steps are applied and the loop continues (at most AUTO_LIMIT
  # per call, then it returns no item with the import still active: call
  # again); it stops at the first item that needs the member. With no
  # pending item left, the import is marked completed.
  #
  # Platform defaults (resolveCompletionatorPlatformState): the item's
  # platform_name mapped (PlatformResolver#resolve_mapped) onto the game's
  # platforms plus STANDARD_PLATFORM_IDS; else mapped onto every platform,
  # in which case a WW release is created on add so the platform becomes
  # valid for the game; else the only option if there is exactly one.
  # The form itself has no side effects; the release is only created when
  # the completion is added.
  #
  # No authorization or test-mode handling here: the controller checks the
  # owner and wraps calls in TestModeRollback.
  class CompletionatorWorkflow
    AUTO_LIMIT = 25
    # The bot's STANDARD_PLATFORM_IDS (config/standardPlatforms.ts): always
    # offered as platform options, whatever the game's releases.
    STANDARD_PLATFORM_IDS = [ 1, 2, 3, 4, 5, 6, 7, 8, 10, 11, 12 ].freeze
    COMPLETION_TYPES = [ "Main Story", "Main Story + Side Content", "Completionist" ].freeze
    DEFAULT_COMPLETION_TYPE = "Main Story"
    UPDATE_FIELDS = %w[type date playtime].freeze
    RELEASE_REGION_CODE = "WW"
    RELEASE_NOTE = "Auto-added from Completionator import platform mapping."

    # A client-facing failure; `code` is the `error` value of the 422.
    class Error < StandardError
      attr_reader :code

      def initialize(code, message)
        super(message)
        @code = code
      end
    end

    Review = Data.define(:item, :next_step, :game, :candidates, :existing_completion, :diff, :form) do
      def self.empty(item = nil, next_step: nil, candidates: [])
        new(item:, next_step:, game: nil, candidates:, existing_completion: nil, diff: nil, form: nil)
      end

      def automatic? = %w[auto_added auto_skipped].include?(next_step)
    end
    AdvanceResult = Data.define(:import, :review, :auto_processed)

    def initialize(import, platform_resolver: PlatformResolver.new, finder: CandidateFinder.new)
      @import = import
      @resolver = platform_resolver
      @finder = finder
    end

    def advance
      auto_processed = 0
      loop do
        item = @import.items.where(status: "pending").order(:row_index).first
        unless item
          @import.update!(status: "completed")
          return AdvanceResult.new(import: @import, review: Review.empty, auto_processed:)
        end
        if auto_processed >= self.class::AUTO_LIMIT
          return AdvanceResult.new(import: @import, review: Review.empty, auto_processed:)
        end

        @import.update!(current_index: item.row_index)
        result = review(item)
        return AdvanceResult.new(import: @import, review: result, auto_processed:) unless result.automatic?

        auto_processed += 1
      end
    end

    # The review for a pending item, applying any automatic step.
    def review(item)
      game = item.gamedb_game_id && GamedbGame.find_by(game_id: item.gamedb_game_id)
      return match(item, game) if game

      candidates = @finder.find_with_fallback(item.game_title)
      if candidates.one?
        game = GamedbGame.find_by(game_id: candidates.first.game_id)
        return match(item, game) if game
      end

      Review.empty(item, next_step: "choose_game", candidates:)
    end

    # handleCompletionatorMatch: records the game on the item, then adds,
    # skips or asks, as in the table above.
    def match(item, game)
      existing = existing_completion(game)
      item.update!(gamedb_game_id: game.game_id, completion_id: existing&.completion_id)
      form = build_form(item, game)

      return review_without_existing(item, game, form) unless existing

      diff = build_diff(existing, item)
      if diff[:fields].empty?
        item.update!(status: "skipped")
        return Review.new(item:, next_step: "auto_skipped", game:, candidates: [], existing_completion: existing, diff:, form:)
      end

      next_step = diff[:confirm_same] ? "confirm_same" : "update_completion"
      Review.new(item:, next_step:, game:, candidates: [], existing_completion: existing, diff:, form:)
    end

    # Adds a new completion for the item's game. Omitted attributes take the
    # review form's defaults; `platform_id: nil` means "other / unknown".
    def add_completion(item, attrs = {})
      game = matched_game!(item)
      form = build_form(item, game)
      completion_type = attrs.fetch("completion_type", form[:completion_type])
      platform_id = attrs.key?("platform_id") ? parse_platform_id(attrs["platform_id"]) : form[:platform_id]
      completed_at = attrs.key?("completed_at") ? parse_date(attrs["completed_at"]) : item.completed_at
      playtime = attrs.key?("final_playtime_hours") ? attrs["final_playtime_hours"] : item.playtime_hrs

      unless COMPLETION_TYPES.include?(completion_type)
        raise Error.new("invalid_completion_type", "completion_type must be one of #{COMPLETION_TYPES.join(', ')}")
      end

      ensure_release(game, platform_id, item)
      completion = UserGameCompletion.create!(
        user_id: @import.user_id, gamedb_game_id: game.game_id, completion_type:, platform_id:,
        completed_at:, final_playtime_hrs: playtime, note: nil
      )
      # completed_at has a database default (today); an unknown date is NULL.
      completion.update_columns(completed_at: nil) if completed_at.nil? && completion.reload.completed_at
      item.update!(status: "added", completion_id: completion.completion_id, error_text: nil)
      item
    end

    # Applies the selected diff fields to the item's existing completion. A
    # selection with nothing left to change skips the item, as in the bot.
    def update_completion(item, fields)
      fields = Array(fields).map(&:to_s)
      unknown = fields - UPDATE_FIELDS
      raise Error.new("invalid_fields", "fields must be a non-empty subset of #{UPDATE_FIELDS.join(', ')}") if fields.empty? || unknown.any?

      completion = item.completion_id && UserGameCompletion.find_by(completion_id: item.completion_id, user_id: @import.user_id)
      raise Error.new("no_existing_completion", "This item has no existing completion to update") unless completion

      selected = build_diff(completion, item)[:fields] & fields
      if selected.empty?
        item.update!(status: "skipped")
        return item
      end

      changes = {}
      changes[:completion_type] = item.completion_type if selected.include?("type")
      changes[:completed_at] = item.completed_at if selected.include?("date")
      changes[:final_playtime_hrs] = item.playtime_hrs if selected.include?("playtime")
      completion.update!(changes)
      item.update!(status: "updated")
      item
    end

    def skip(item)
      item.update!(status: "skipped")
      item
    end

    private

    def review_without_existing(item, game, form)
      if form[:platform_id]
        add_completion(item)
        return Review.new(item:, next_step: "auto_added", game:, candidates: [], existing_completion: nil, diff: nil, form:)
      end

      Review.new(item:, next_step: "add_completion", game:, candidates: [], existing_completion: nil, diff: nil, form:)
    end

    def matched_game!(item)
      game = item.gamedb_game_id && GamedbGame.find_by(game_id: item.gamedb_game_id)
      raise Error.new("no_game_matched", "Match a game to this item first") unless game

      game
    end

    # Member.getCompletionByGameId: the latest completion of the game.
    def existing_completion(game)
      UserGameCompletion.includes(:game, :platform)
        .where(user_id: @import.user_id, gamedb_game_id: game.game_id)
        .order(completed_at: :desc, created_at: :desc).first
    end

    # buildCompletionUpdate / shouldConfirmCompletionMatch. Dates compare by
    # day; playtime differs when missing or at least an hour apart.
    def build_diff(existing, item)
      fields = []
      fields << "type" if item.completion_type.present? && item.completion_type != existing.completion_type
      existing_date = existing.completed_at&.to_date
      incoming_date = item.completed_at&.to_date
      fields << "date" if incoming_date && existing_date != incoming_date
      if item.playtime_hrs
        current = existing.final_playtime_hrs
        fields << "playtime" if current.nil? || (current - item.playtime_hrs).abs >= 1
      end

      { fields:, confirm_same: existing_date.present? && incoming_date.present? && existing_date != incoming_date }
    end

    def build_form(item, game)
      options = platform_options(game)
      platform_id, creates_release = default_platform(item, game, options)
      if platform_id && options.none? { |platform| platform.platform_id == platform_id }
        options += GamedbPlatform.where(platform_id: platform_id).to_a
      end

      {
        completion_type: default_completion_type(item),
        platform_id:,
        creates_release:,
        platforms: options,
        date_choice: item.completed_at ? "csv" : "unknown",
        completed_at: item.completed_at,
        final_playtime_hours: item.playtime_hrs&.to_f
      }
    end

    def default_completion_type(item)
      [ CompletionatorCsvParser.map_type(item.source_type), item.completion_type ]
        .find { |type| COMPLETION_TYPES.include?(type) } || DEFAULT_COMPLETION_TYPE
    end

    # [platform_id, creates_release]
    def default_platform(item, game, options)
      if item.platform_name.present?
        on_game = @resolver.resolve_mapped(item.platform_name, among: options)
        return [ on_game, false ] if on_game

        mapped = mapped_platform_id(item)
        return [ mapped, true ] if mapped
      end
      return [ options.first.platform_id, false ] if options.one?

      [ nil, false ]
    end

    def mapped_platform_id(item)
      return if item.platform_name.blank?

      @resolver.resolve_mapped(item.platform_name, among: all_platforms)
    end

    # The game's platforms (its platform links and its release platforms),
    # sorted by name, then the standard platforms it lacks (getPlatformsForGameWithStandard).
    def platform_options(game)
      game_ids = game_platform_ids(game)
      own = GamedbPlatform.where(platform_id: game_ids).order(:platform_name).to_a
      standard = GamedbPlatform.where(platform_id: self.class::STANDARD_PLATFORM_IDS - game_ids).order(:platform_name).to_a
      own + standard
    end

    def game_platform_ids(game)
      (GamedbGamePlatform.where(game_id: game.game_id).pluck(:platform_id) +
        GamedbRelease.where(game_id: game.game_id).pluck(:platform_id)).uniq
    end

    def all_platforms
      @all_platforms ||= GamedbPlatform.order(:platform_id).to_a
    end

    # ensureCompletionatorPlatformRelease: only for the item's mapped
    # platform, only when the game lacks it, and only if the WW region exists.
    def ensure_release(game, platform_id, item)
      return unless platform_id && platform_id == mapped_platform_id(item)
      return if game_platform_ids(game).include?(platform_id)

      region = GamedbRegion.find_by(region_code: RELEASE_REGION_CODE)
      return unless region

      GamedbRelease.create!(game_id: game.game_id, platform_id:, region_id: region.region_id,
        release_date: game.initial_release_date, notes: RELEASE_NOTE)
      game.touch
    end

    def parse_platform_id(value)
      return if value.blank?

      id = Integer(value.to_s, 10, exception: false)
      raise Error.new("invalid_platform", "Unknown platform_id #{value.inspect}") unless id && GamedbPlatform.exists?(platform_id: id)

      id
    end

    def parse_date(value)
      return if value.blank?

      Time.zone.parse(value.to_s) || raise(ArgumentError)
    rescue ArgumentError
      raise Error.new("invalid_completed_at", "completed_at must be an ISO 8601 date")
    end
  end
end
