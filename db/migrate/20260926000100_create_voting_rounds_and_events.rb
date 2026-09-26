# frozen_string_literal: true

# The backend-owned voting round lifecycle. A voting_rounds row is keyed by the
# round members nominate for, vote on and win — no offset to the round being
# played, unlike bot_voting_info, whose rows changed meaning once a round was
# decided. voting_events is the outbox the Discord bot polls for the posts a
# phase change calls for (reminders, vote panels, results, winner threads).
class CreateVotingRoundsAndEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :voting_rounds, primary_key: :round_number, id: :bigint, default: nil do |t|
      # Nominations close and voting opens at the same instant.
      t.datetime :voting_opens_at, precision: 6, null: false
      t.datetime :voting_closes_at, precision: 6, null: false
      # Set once the tally has been finalized into winners and/or ties.
      t.datetime :closed_at, precision: 6
      # Set once every category's winner is recorded; the next round is
      # created at the same time.
      t.datetime :decided_at, precision: 6
      t.string :month_year, limit: 200, null: false
      # Categories whose top vote count was shared, awaiting an admin pick:
      # { "gotm" => [gamedb_game_id, ...], "nr_gotm" => [...] }.
      t.jsonb :pending_ties, null: false, default: {}
      t.timestamps
    end
    # VotingRound.current is the lowest undecided round.
    add_index :voting_rounds, :round_number, where: "decided_at IS NULL", name: "ix_voting_rounds_undecided"

    create_table :voting_events do |t|
      t.bigint :round_number, null: false
      t.string :kind, limit: 64, null: false
      t.jsonb :payload, null: false, default: {}
      t.datetime :available_at, precision: 6, null: false
      # A stale event is never delivered: a reminder is pointless once voting
      # opens, and so are the vote panels once it closes.
      t.datetime :expires_at, precision: 6
      # Claim lease: the bot claims, posts, then acks. An unacked claim becomes
      # claimable again when the lease runs out.
      t.datetime :claimed_until, precision: 6
      t.datetime :delivered_at, precision: 6
      t.integer :attempts, null: false, default: 0
      t.timestamps
    end
    # One event of each kind per round: re-running the sweep never re-posts.
    add_index :voting_events, %i[round_number kind], unique: true, name: "ux_voting_events_round_kind"
    add_index :voting_events, :available_at, where: "delivered_at IS NULL", name: "ix_voting_events_pending"
  end
end
