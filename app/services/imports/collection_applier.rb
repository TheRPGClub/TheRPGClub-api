# frozen_string_literal: true

module Imports
  # Adds one game to a user's collection on behalf of an import item, and
  # turns the outcome into the item's status/result_reason (the bot's
  # applySteamImportSelection / applyCsvImportSelection ladder):
  #
  #   result = Imports::CollectionApplier.new(user_id: import.user_id)
  #     .apply(game_id: 42, platform_id: steam_id, ownership_type: "Digital", note: nil)
  #
  #   status    reason                 when
  #   "added"   nil                    entry created (the caller supplies its own
  #                                    reason: auto_match, manual_remap, csv_*)
  #   "added"   "platform_unresolved"  entry created without a platform because the
  #                                    caller passed platform_unresolved: true
  #   "skipped" "duplicate"            uq_user_game_collections_dedup already holds
  #                                    (user, game, platform, ownership_type)
  #   "failed"  "add_failed"           unknown ownership type, validation or other
  #                                    database error; `error` is a client-safe
  #                                    message
  #
  # `entry` is the created UserGameCollection (nil unless added). The insert
  # runs in a savepoint, so a duplicate or constraint error never poisons an
  # enclosing transaction (e.g. TestModeRollback). Authorization is the
  # caller's job: check the import's owner before applying.
  class CollectionApplier
    OWNERSHIP_TYPES = %w[Digital Physical Subscription Other].freeze
    DEFAULT_OWNERSHIP = "Digital"

    Result = Data.define(:status, :reason, :entry, :error) do
      def added? = status == "added"
      def skipped? = status == "skipped"
      def failed? = status == "failed"
    end

    # The CSV ownership rule: case-insensitive match on OWNERSHIP_TYPES, blank
    # means Digital, anything else is nil (invalid).
    def self.normalize_ownership(raw)
      value = raw.to_s.strip
      return DEFAULT_OWNERSHIP if value.empty?

      OWNERSHIP_TYPES.find { |type| type.casecmp?(value) }
    end

    def initialize(user_id:)
      @user_id = user_id
    end

    def apply(game_id:, platform_id: nil, ownership_type: DEFAULT_OWNERSHIP, note: nil, platform_unresolved: false)
      unless OWNERSHIP_TYPES.include?(ownership_type)
        return failure("Unknown ownership type #{ownership_type.inspect}; expected one of #{OWNERSHIP_TYPES.join(', ')}")
      end

      entry = UserGameCollection.transaction(requires_new: true) do
        UserGameCollection.create!(
          user_id: @user_id, gamedb_game_id: game_id, platform_id: platform_id,
          ownership_type: ownership_type, note: note.presence
        )
      end
      Result.new(status: "added", reason: platform_unresolved ? "platform_unresolved" : nil, entry: entry, error: nil)
    rescue ActiveRecord::RecordNotUnique
      Result.new(status: "skipped", reason: "duplicate", entry: nil, error: nil)
    rescue ActiveRecord::RecordInvalid => error
      failure(error.record.errors.full_messages.to_sentence)
    rescue ActiveRecord::StatementInvalid => error
      # The raw database message names constraints and values; log it, and
      # keep the item's error_text generic (as render_duplicate_value does).
      Rails.logger.warn("Imports::CollectionApplier: #{error.class}: #{error.message}")
      failure("Could not add the game to the collection")
    end

    private

    def failure(message)
      Result.new(status: "failed", reason: "add_failed", entry: nil, error: message)
    end
  end
end
