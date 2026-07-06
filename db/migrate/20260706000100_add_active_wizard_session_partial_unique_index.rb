# frozen_string_literal: true

# Adds the partial unique index the bot's admin-wizard upsert needs
# (therpgclub-api #160). The bot's saveSession (rpg_club_admin_wizard_sessions)
# runs:
#
#   INSERT ... ON CONFLICT (command_key, owner_user_id, channel_id)
#   WHERE status = 'ACTIVE' DO UPDATE ...
#
# to keep at most one ACTIVE wizard session per command/owner/channel. Postgres
# only infers an ON CONFLICT arbiter from a *partial* unique index on exactly
# those three columns carrying the `status = 'ACTIVE'` predicate. The schema
# shipped only the full four-column `ux_rpg_club_admin_wiz_active` (an
# Oracle -> Postgres port artifact: Oracle had no partial-unique equivalent),
# which cannot serve as that arbiter — so every `/admin nextround-setup` failed
# with "there is no unique or exclusion constraint matching the ON CONFLICT
# specification" the moment it saved its wizard session, before it ever reached
# the thread writes the bug report first suspected.
#
# Additive: the full index is intentionally kept. The bot's
# closeActiveAdminWizardSession relies on it — it deletes the prior historical
# row before promoting ACTIVE -> COMPLETED/CANCELLED to avoid a same-status
# collision. This migration only supplies the missing partial arbiter for the
# ACTIVE upsert.
class AddActiveWizardSessionPartialUniqueIndex < ActiveRecord::Migration[8.1]
  TABLE = :rpg_club_admin_wizard_sessions
  INDEX_NAME = "ux_rpg_club_admin_wiz_one_active"

  def up
    return unless table_exists?(TABLE)

    add_index TABLE, %i[command_key owner_user_id channel_id],
      unique: true,
      where: "status = 'ACTIVE'",
      name: INDEX_NAME,
      if_not_exists: true
  end

  def down
    remove_index TABLE, name: INDEX_NAME, if_exists: true
  end
end
