# frozen_string_literal: true

# Bot job activity list (web parity 2, Wave 2): a plain-text summary set at
# enqueue, the bot's result text on a done ack, and a per-claim lease expiry
# so each kind can have its own lease length.
class AddSummaryResultAndLeaseToBotJobs < ActiveRecord::Migration[8.1]
  def up
    # The default lets the previous release, which still serves while this
    # runs (fly release_command), insert jobs without a summary; the API
    # shows the kind for a blank one.
    add_column :bot_jobs, :summary, :string, limit: 200, default: ""
    add_column :bot_jobs, :result_text, :text
    add_column :bot_jobs, :lease_expires_at, :datetime

    # Jobs queued before summaries existed read as their kind ("Giveaway hub
    # refresh"); open claims keep the old five minute lease. Claims the
    # previous release makes after this runs have no lease expiry, which
    # BotJob treats as the default lease.
    execute <<~SQL.squish
      UPDATE bot_jobs SET summary = initcap(replace(kind, '_', ' '))
    SQL
    execute <<~SQL.squish
      UPDATE bot_jobs SET lease_expires_at = claimed_at + interval '5 minutes' WHERE status = 'claimed'
    SQL
    change_column_null :bot_jobs, :summary, false

    remove_index :bot_jobs, name: "ix_bot_jobs_claimed"
    add_index :bot_jobs, :lease_expires_at, where: "status = 'claimed'", name: "ix_bot_jobs_claimed"
  end

  def down
    remove_index :bot_jobs, name: "ix_bot_jobs_claimed"
    add_index :bot_jobs, :claimed_at, where: "status = 'claimed'", name: "ix_bot_jobs_claimed"
    remove_column :bot_jobs, :lease_expires_at
    remove_column :bot_jobs, :result_text
    remove_column :bot_jobs, :summary
  end
end
