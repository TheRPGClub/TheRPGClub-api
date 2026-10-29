# frozen_string_literal: true

module Imports
  # Turns an IGDB id picked during an import into a GameDB game: the
  # owner-safe counterpart of the admin-only POST /api/v1/games (the bot's
  # importGameFromIgdb). Import item endpoints call it after checking that
  # the current principal owns the item; it never goes through GamesController.
  #
  #   result = Imports::IgdbGameResolver.new.resolve(params[:igdb_id])
  #   result.ok?     # => true when result.game is set
  #   result.game    # GamedbGame
  #   result.created # true when this call imported it from IGDB
  #   result.error   # nil | "invalid_igdb_id" | "igdb_game_not_found"
  #                  #     | "igdb_not_configured" | "igdb_request_failed"
  #
  # An igdb_id already in GameDB short-circuits (no IGDB call, created: false).
  # Otherwise Gamedb::IgdbGameImporter#import! creates the game, its taxonomy
  # and releases, then its images. If only the image step fails, the game is
  # already committed, so it is returned anyway (images can be refreshed later
  # by an admin). Suggested HTTP mapping for callers: invalid_igdb_id and
  # igdb_not_configured 422, igdb_game_not_found 404, igdb_request_failed 502.
  class IgdbGameResolver
    Result = Data.define(:game, :created, :error) do
      def ok? = error.nil?
    end

    IMAGE_ERRORS = [
      Gamedb::IgdbImageImporter::MissingIgdbGameError,
      Gamedb::IgdbImageImporter::MissingIgdbIdError,
      Gamedb::GameImageStorage::InvalidImageError,
      Backblaze::Client::ConfigurationError,
      Backblaze::Client::RequestError
    ].freeze

    def initialize(importer: nil)
      @importer = importer
    end

    def resolve(raw_igdb_id)
      igdb_id = Integer(raw_igdb_id.to_s, 10, exception: false)
      return failure("invalid_igdb_id") unless igdb_id&.positive?

      existing = GamedbGame.find_by(igdb_id: igdb_id)
      return Result.new(game: existing, created: false, error: nil) if existing

      import(igdb_id)
    end

    private

    def import(igdb_id)
      result = importer.import!(igdb_id)
      Result.new(game: result.game, created: result.created, error: nil)
    rescue Gamedb::IgdbGameImporter::MissingIgdbGameError
      failure("igdb_game_not_found")
    rescue Igdb::Client::ConfigurationError
      failure("igdb_not_configured")
    rescue Igdb::Client::RequestError
      failure("igdb_request_failed")
    rescue *IMAGE_ERRORS => error
      game = GamedbGame.find_by(igdb_id: igdb_id)
      raise error unless game

      Rails.logger.warn("Imports::IgdbGameResolver: images for IGDB #{igdb_id} failed: #{error.class}: #{error.message}")
      Result.new(game: game, created: true, error: nil)
    end

    # Built lazily, so a resolve that finds an existing game never builds it.
    def importer
      @importer ||= Gamedb::IgdbGameImporter.new
    end

    def failure(code)
      Result.new(game: nil, created: false, error: code)
    end
  end
end
