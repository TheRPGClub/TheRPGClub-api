# frozen_string_literal: true

# A live event (web parity 2, #336): the bot's `/live-stream create`, started
# from the site. A Moderator saves the topic, times and an optional image;
# the `live_event_create` bot job then makes the forum thread and the Discord
# scheduled event, recording each id here as it is made, so a retried job
# skips the steps already done.
#
#   queued          saved, waiting for the bot
#   thread_created  the forum thread exists (discord_thread_id set)
#   created         the scheduled event exists too (discord_event_id set)
#   failed          the bot gave up: it said so, or its bot job failed (acked
#                   failed, or out of attempts); the error is on bot_job_id
class LiveEvent < ApplicationRecord
  STATUSES = %w[queued thread_created created failed].freeze
  TOPIC_MAX = 100
  IMAGE_URL_MAX = 1000
  SNOWFLAKE = /\A\d{1,30}\z/

  belongs_to :bot_job, optional: true
  belongs_to :created_by, class_name: "RpgClubUser", foreign_key: :created_by_user_id,
    primary_key: :user_id, optional: true, inverse_of: false

  normalizes :topic, with: ->(value) { value.to_s.squish }
  normalizes :image_url, with: ->(value) { value.to_s.strip.presence }

  validates :topic, presence: true, length: { maximum: TOPIC_MAX }
  validates :starts_at, :ends_at, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :image_url, length: { maximum: IMAGE_URL_MAX }, allow_nil: true
  validates :discord_thread_id, :discord_event_id, format: { with: SNOWFLAKE }, allow_nil: true
  validate :image_url_is_http
  validate :ends_after_start
  validate :starts_in_future, on: :create

  # Queues the bot job that makes the thread and event. Call inside the
  # transaction that saves the event.
  def enqueue_creation!(requested_by:)
    job = BotJob.enqueue!(
      kind: "live_event_create",
      summary: %(Create the live event "#{topic}" (forum thread and Discord event)),
      payload: { live_event_id: id },
      requested_by: requested_by
    )
    update!(bot_job: job)
  end

  # Called by BotJob when jobs end failed: their events will not be made, so
  # they read as failed (an event the bot finished is left alone).
  def self.bot_jobs_failed!(job_ids, now: Time.current)
    where(bot_job_id: job_ids).where.not(status: %w[created failed])
      .update_all(status: "failed", updated_at: now)
  end

  private

  def image_url_is_http
    return if image_url.nil?

    uri = URI.parse(image_url)
    return if uri.is_a?(URI::HTTP) && uri.host.present?

    errors.add(:image_url, "must be an http or https URL")
  rescue URI::InvalidURIError
    errors.add(:image_url, "must be an http or https URL")
  end

  def ends_after_start
    return if starts_at.blank? || ends_at.blank? || ends_at > starts_at

    errors.add(:ends_at, "must be after the start")
  end

  def starts_in_future
    return if starts_at.blank? || starts_at > Time.current

    errors.add(:starts_at, "must be in the future")
  end
end
