# frozen_string_literal: true

# role_dev (AddRoleDevToRpgClubUsers) starts false for everyone, so until a
# role sync rewrites it a Superadmin acting through the bot reads as
# non-staff (spec #347). Sign-in already records the dev role on each
# session token (`is_dev`), so this marks the members whose latest
# unexpired session (at most 7 days old) was issued with it. It only ever
# sets true; a member without a recent sign-in waits for the role sync
# (memberscan) run after deploy, which stays the authority either way.
class BackfillRoleDevFromSessions < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL.squish
      UPDATE rpg_club_users SET role_dev = TRUE, updated_at = NOW()
      WHERE role_dev = FALSE AND user_id IN (
        SELECT user_id FROM (
          SELECT DISTINCT ON (user_id) user_id, is_dev FROM user_session_tokens
          WHERE expires_at > NOW()
          ORDER BY user_id, created_at DESC, id DESC
        ) latest
        WHERE latest.is_dev
      )
    SQL
  end

  # A backfill of a flag the role sync keeps current; nothing to undo.
  def down; end
end
