# frozen_string_literal: true

# News Hub image renewal (spec #355, ticket #358): at most one open
# (queued or claimed) news_images_renew bot job per message. The feed queues
# a renewal each time it serves an expired image address; this index makes
# every later attempt a no-op until the bot finishes the first, however many
# requests race (BotJob.enqueue_once!).
class AddOpenNewsImageRenewalIndexToBotJobs < ActiveRecord::Migration[8.1]
  def change
    add_index :bot_jobs, "(payload ->> 'message_id')", unique: true, name: "ux_bot_jobs_one_open_news_images_renew",
      where: "kind = 'news_images_renew' AND status IN ('queued', 'claimed')"
  end
end
