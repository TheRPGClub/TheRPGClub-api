# frozen_string_literal: true

# One run of the image backfill (web parity 2, #338): Gamedb::ImageBackfillJob
# imports IGDB images for every game with none stored, and counts its progress
# here for the website to show.
#
#   total    games that had no images when the run started
#   done     games whose images were imported
#   skipped  games with no IGDB id
#   failed   games whose import raised; last_error holds the latest message
#
# At most one run is queued or running (a partial unique index). A run whose
# row has not moved for STALE_AFTER is taken to have died with its process,
# and starting or reading a run marks it failed (fail_stale!).
class ImageBackfillRun < ApplicationRecord
  STATUSES = %w[queued running completed failed].freeze
  IN_PROGRESS = %w[queued running].freeze
  STALE_AFTER = 30.minutes
  STALE_ERROR = "Stopped reporting progress"

  # Starting while another run is queued or running.
  class InProgress < StandardError; end

  belongs_to :started_by, class_name: "RpgClubUser", foreign_key: :started_by_user_id,
    primary_key: :user_id, optional: true, inverse_of: false

  validates :status, inclusion: { in: STATUSES }

  scope :in_progress, -> { where(status: IN_PROGRESS) }

  # Queues a new run and its job. Raises InProgress while a live run exists.
  def self.start!(started_by_user_id:, now: Time.current)
    run = transaction do
      fail_stale!(now)
      raise InProgress if in_progress.exists?

      create!(started_by_user_id: started_by_user_id)
    end
    Gamedb::ImageBackfillJob.perform_later(run.id)
    run
  rescue ActiveRecord::RecordNotUnique
    raise InProgress
  end

  # Marks failed every queued or running run whose row has not moved for
  # STALE_AFTER (its process died: a deploy or restart). Run before starting
  # and before reading, so the site never shows a dead run as live.
  def self.fail_stale!(now = Time.current)
    in_progress.where(updated_at: ..(now - STALE_AFTER))
      .update_all(status: "failed", last_error: STALE_ERROR, finished_at: now, updated_at: now)
  end

  def in_progress?
    IN_PROGRESS.include?(status)
  end
end
