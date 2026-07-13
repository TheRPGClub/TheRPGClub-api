# frozen_string_literal: true

class AddVoteEndsAtToBotVotingInfo < ActiveRecord::Migration[8.1]
  def change
    # Explicit voting-deadline override. NULL falls back to the default
    # Friday -> Sunday window computed from next_vote_at (see BotVotingInfo).
    add_column :bot_voting_info, :vote_ends_at, :datetime, precision: 6
  end
end
