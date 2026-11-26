# frozen_string_literal: true

# A Patch (GLOSSARY.md "Patch"; spec api#510, ticket api#511): one numbered,
# dated post of Patch Notes. Admins and Superadmins write it as a draft that
# nobody else sees, then publish it to the website.
#
# `number` comes from the database's own sequence on insert, so Patches are
# numbered in order and a number is never handed out again, even once its
# Patch is unpublished or deleted.
#
# The website keeps three texts in step: `rich_body` (the Plate value it
# edits), `body` (the full text as Discord markdown) and `cut_body` (that
# markdown cut to Discord's limit, which the bot posts). The API stores them
# as given.
#
# Publishing puts a Patch on the website only. Staff then post it to Discord
# (queue_post!) and push later edits (queue_post_edit!); unpublishing a posted
# Patch takes the post down. Each queues a bot job (POST_KINDS) that carries
# the Patch's number in its payload; the bot records the message it posted
# (record_post!) or removed (clear_post!). `edited_since_post` marks a posted
# Patch whose text changed since the post last matched it.
class Patch < ApplicationRecord
  DRAFT = "draft"
  PUBLISHED = "published"
  STATUSES = [ DRAFT, PUBLISHED ].freeze
  TITLE_MAX = 100
  POST_KINDS = %w[patch_post patch_edit patch_delete].freeze
  # The fields the Discord post is made from.
  POST_TEXT = %w[title rich_body body cut_body].freeze
  OPEN_JOB = %w[queued claimed].freeze

  validates :status, inclusion: { in: STATUSES }
  validates :title, length: { maximum: TITLE_MAX }

  normalizes :title, with: ->(value) { value.strip.presence }

  scope :published, -> { where(status: PUBLISHED) }

  before_update { self.edited_since_post = true if posted? && POST_TEXT.any? { |field| will_save_change_to_attribute?(field) } }

  def draft? = status == DRAFT
  def published? = status == PUBLISHED

  def publish!
    update!(status: PUBLISHED, published_at: Time.current)
  end

  # Back to a draft, taking a posted Patch's Discord post down with it.
  def unpublish!(requested_by: nil)
    transaction do
      update!(status: DRAFT, published_at: nil)
      queue_post_delete!(requested_by: requested_by) if posted?
    end
  end

  # Whether the bot has recorded a Discord post of it.
  def posted? = post_message_id.present?

  # The bot jobs for its Discord post, found by its number (never reused).
  def post_jobs = BotJob.where(kind: POST_KINDS).where("payload->>'number' = ?", number.to_s)

  # The latest of them, so staff see its progress after a reload.
  def post_job = post_jobs.includes(:requested_by).order(id: :desc).first

  # Whether a patch_post is queued or claimed and not yet acked.
  def post_queued? = post_jobs.where(kind: "patch_post", status: OPEN_JOB).exists?

  # Whether a patch_delete is queued or claimed and not yet acked.
  def post_removing? = post_jobs.where(kind: "patch_delete", status: OPEN_JOB).exists?

  # Whether it has a Discord post, or a post job on its way that may still
  # make or touch one. Deleting it then would leave the post behind.
  def post_pending? = posted? || post_jobs.where(status: OPEN_JOB).exists?

  def queue_post!(requested_by:)
    BotJob.enqueue!(kind: "patch_post", summary: %(Post #{label} to #patch-notes), payload: post_text,
      requested_by: requested_by)
  end

  def queue_post_edit!(requested_by:)
    BotJob.enqueue!(kind: "patch_edit", summary: %(Update the #patch-notes post of #{label}),
      payload: post_text.merge(post_message), requested_by: requested_by)
  end

  def queue_post_delete!(requested_by: nil)
    BotJob.enqueue!(kind: "patch_delete", summary: "Remove the #patch-notes post of Patch #{number}",
      payload: { number: number, **post_message }, requested_by: requested_by)
  end

  # The bot posted (or edited) message `message_id` in `channel_id`. A new
  # message is stamped posted now; the edited one keeps its time. Either way
  # the post matches the Patch again. A post that lands after the Patch was
  # unpublished is taken straight down.
  def record_post!(channel_id:, message_id:)
    with_lock do
      fields = { post_channel_id: channel_id, post_message_id: message_id, edited_since_post: false }
      fields[:posted_at] = Time.current unless post_message_id == message_id
      update!(fields)
      queue_post_delete! if draft?
    end
  end

  # The bot removed message `message_id`. A late removal of an older message
  # leaves a newer post alone.
  def clear_post!(message_id:)
    with_lock do
      next unless post_message_id == message_id

      update!(post_channel_id: nil, post_message_id: nil, posted_at: nil, edited_since_post: false)
    end
  end

  # The published Patches just before and after this one, by number.
  def previous_number = Patch.published.where(number: ...number).maximum(:number)
  def next_number = Patch.published.where("number > ?", number).minimum(:number)

  # How many changes it lists as New, Improved and Fixed (PatchNotes.counts).
  def counts = PatchNotes.counts(rich_body)

  private

  def label = title ? %(Patch #{number} "#{title}") : "Patch #{number}"

  def post_text = { number: number, title: title, cut_body: cut_body, published_at: published_at&.utc&.iso8601(3) }

  def post_message = { channel_id: post_channel_id, message_id: post_message_id }
end
