# frozen_string_literal: true

# News Hub image renewal cooldown (spec #355): the feed queues no renewal for
# a message whose last renewal ended (done or failed) within the cooldown
# (NewsHub::BotJobs::RENEWAL_COOLDOWN). This index serves that lookup by
# message and finish time.
class AddFinishedNewsImageRenewalIndexToBotJobs < ActiveRecord::Migration[8.1]
  def change
    add_index :bot_jobs, "(payload ->> 'message_id'), finished_at", name: "ix_bot_jobs_finished_news_images_renew",
      where: "kind = 'news_images_renew' AND status IN ('done', 'failed')"
  end
end
