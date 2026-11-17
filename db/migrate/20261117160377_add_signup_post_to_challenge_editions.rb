# frozen_string_literal: true

# Secret Santa "Gift tags" (spec #376; design picks bot 7C): the bot posts an
# Edition's sign-up opening post, then stores its Discord channel and message
# id on the Edition, so the later Edition posts (closing soon, closed or
# cancelled, revealed) can reply to it. Both set together, or neither.
class AddSignupPostToChallengeEditions < ActiveRecord::Migration[8.1]
  def change
    change_table :challenge_editions, bulk: true do |t|
      t.string :signup_post_channel_id, limit: 30
      t.string :signup_post_message_id, limit: 30
      t.check_constraint "(signup_post_channel_id IS NULL) = (signup_post_message_id IS NULL)",
        name: "ck_challenge_editions_signup_post"
    end
  end
end
