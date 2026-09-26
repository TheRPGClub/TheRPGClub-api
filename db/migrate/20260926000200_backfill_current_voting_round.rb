# frozen_string_literal: true

# Seeds voting_rounds with the round currently being nominated or voted on,
# derived from bot_voting_info and the recorded winners (see Voting::Backfill).
# Earlier rounds need no row: VotingRound treats every round below the current
# one as finished.
class BackfillCurrentVotingRound < ActiveRecord::Migration[8.1]
  def up
    # The table was created earlier in this same migrate run.
    VotingRound.reset_column_information
    Voting::Backfill.call
  end

  def down
    # Nothing to undo beyond the table drop in the previous migration.
  end
end
