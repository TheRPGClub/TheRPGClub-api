# frozen_string_literal: true

module Gamedb
  # Imports IGDB images for every game with none stored, recording progress
  # on an ImageBackfillRun (web parity 2, #338). Replaces the bot's
  # `/superadmin download-missing-images`: a game with no IGDB id counts as
  # skipped, any other import error as failed. Missing IGDB or Backblaze
  # configuration stops the run, since every game would fail the same way.
  class ImageBackfillJob < ApplicationJob
    queue_as :default

    # Gap between games, as the bot kept, to stay within IGDB's rate limit.
    class_attribute :pause_seconds, default: 0.25

    CONFIGURATION_ERRORS = [ Igdb::Client::ConfigurationError, Backblaze::Client::ConfigurationError ].freeze

    def perform(run_id)
      run = ImageBackfillRun.find_by(id: run_id)
      return unless run&.status == "queued"

      game_ids = GamedbGame.where.missing(:images).order(:game_id).pluck(:game_id)
      run.update!(status: "running", total: game_ids.size, started_at: Time.current)
      backfill(run, game_ids)
      run.update!(status: "completed", finished_at: Time.current)
    rescue *CONFIGURATION_ERRORS => error
      run.update!(status: "failed", last_error: error.message, finished_at: Time.current)
    rescue StandardError => error
      run&.update(status: "failed", last_error: error.message.truncate(2000), finished_at: Time.current)
      raise
    end

    private

    def backfill(run, game_ids)
      importer = IgdbImageImporter.new
      game_ids.each_with_index do |game_id, index|
        sleep(pause_seconds) if index.positive? && pause_seconds.positive?
        import_one(run, importer, game_id)
      end
    end

    def import_one(run, importer, game_id)
      importer.import!(game_id)
      run.increment!(:done, touch: true)
    rescue IgdbImageImporter::MissingIgdbIdError
      run.increment!(:skipped, touch: true)
    rescue *CONFIGURATION_ERRORS
      raise
    rescue StandardError => error
      run.update!(failed: run.failed + 1, last_error: "Game #{game_id}: #{error.message}".truncate(2000))
    end
  end
end
