# frozen_string_literal: true

module NewsHub
  # The work the API asks the bot to do for the News Hub (spec #355, ticket
  # #358). Both kinds carry the News Hub's key as `feature_key`
  # (BotJob::FEATURE_WORK) and post nothing.
  #
  # news_images_renew, payload { message_id, channel_id, feature_key }: the
  # feed served a News Item whose Discord image address has expired. The bot
  # fetches the message from `channel_id` and records it again
  # (PUT /api/v1/news_items/:message_id) with fresh addresses, or removes the
  # News Item when the message is gone. At most one is open per message, and
  # none is queued for a message whose last renewal ended (done or failed)
  # less than RENEWAL_COOLDOWN ago, so a renewal that failed or left the
  # address expired is not retried on every load.
  #
  # news_catch_up, payload { from_state, to_state, feature_key }: the News
  # Hub's Feature Flag left Off, so the bot scans the News Categories'
  # threads for what was posted meanwhile.
  module BotJobs
    RENEW_IMAGES = "news_images_renew"
    CATCH_UP = "news_catch_up"
    RENEWAL_COOLDOWN = 6.hours

    # Queues a renewal for each of `items` with an image address expired at
    # `now`, except those with one already open or one that ended within
    # RENEWAL_COOLDOWN. Returns how many were queued.
    def self.renew_expired_images!(items, now: Time.current)
      expired = items.select { |item| item.images_expired?(now) }
      cooling = recently_renewed(expired.map(&:message_id), now)
      jobs = expired.reject { |item| cooling.include?(item.message_id) }.map do |item|
        { summary: "Renew the expired image addresses of News Item #{item.message_id}",
          payload: { message_id: item.message_id, channel_id: item.channel_id } }
      end
      BotJob.enqueue_once!(kind: RENEW_IMAGES, jobs: jobs)
    end

    # The ones of `message_ids` whose renewal ended within RENEWAL_COOLDOWN
    # of `now`.
    def self.recently_renewed(message_ids, now)
      return Set.new if message_ids.empty?

      BotJob.where(kind: RENEW_IMAGES, status: %w[done failed], finished_at: (now - RENEWAL_COOLDOWN)..)
        .where("payload ->> 'message_id' IN (?)", message_ids)
        .distinct.pluck(Arel.sql("payload ->> 'message_id'")).to_set
    end
    private_class_method :recently_renewed

    # Queues the catch-up scan for a Feature Flag change from `from_state` (Off)
    # to `to_state`, requested by the staff member `by` (a Discord user id).
    def self.catch_up!(from_state:, to_state:, by:)
      BotJob.enqueue!(kind: CATCH_UP, summary: "News Hub catch-up: the Feature Flag went from #{from_state} to #{to_state}",
        payload: { from_state: from_state, to_state: to_state }, requested_by: by)
    end
  end
end
