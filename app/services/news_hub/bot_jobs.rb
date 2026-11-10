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
  # News Item when the message is gone. At most one is open per message.
  #
  # news_catch_up, payload { from_state, to_state, feature_key }: the News
  # Hub's Feature Flag left Off, so the bot scans the News Categories'
  # threads for what was posted meanwhile.
  module BotJobs
    RENEW_IMAGES = "news_images_renew"
    CATCH_UP = "news_catch_up"

    # Queues a renewal for each of `items` with an image address expired at
    # `now`, except those with one already open. Returns how many were queued.
    def self.renew_expired_images!(items, now: Time.current)
      jobs = items.select { |item| item.images_expired?(now) }.map do |item|
        { summary: "Renew the expired image addresses of News Item #{item.message_id}",
          payload: { message_id: item.message_id, channel_id: item.channel_id } }
      end
      BotJob.enqueue_once!(kind: RENEW_IMAGES, jobs: jobs)
    end
  end
end
