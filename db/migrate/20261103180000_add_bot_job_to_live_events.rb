# frozen_string_literal: true

# The live_event_create bot job behind each live event, so the site can show
# the bot's error when it fails (web parity 2 review).
class AddBotJobToLiveEvents < ActiveRecord::Migration[8.1]
  def change
    add_reference :live_events, :bot_job, foreign_key: { on_delete: :nullify }
  end
end
