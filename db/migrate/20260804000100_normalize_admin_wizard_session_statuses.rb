# frozen_string_literal: true

# Keep the admin-wizard session statuses consistent with the Rails model and
# API contract. The imported schema used Oracle-style uppercase values, while
# the controller and bot use lowercase values.
class NormalizeAdminWizardSessionStatuses < ActiveRecord::Migration[8.1]
  TABLE = :rpg_club_admin_wizard_sessions
  CHECK_CONSTRAINT = "ck_rpg_club_admin_wiz_sess_status"
  PARTIAL_INDEX = "ux_rpg_club_admin_wiz_one_active"

  def up
    return unless table_exists?(TABLE)

    execute <<~SQL
      ALTER TABLE rpg_club_admin_wizard_sessions
        DROP CONSTRAINT IF EXISTS #{CHECK_CONSTRAINT};
      DROP INDEX IF EXISTS #{PARTIAL_INDEX};
      UPDATE rpg_club_admin_wizard_sessions
      SET status = LOWER(status)
      WHERE status IN ('ACTIVE', 'COMPLETED', 'CANCELLED');
      ALTER TABLE rpg_club_admin_wizard_sessions
        ALTER COLUMN status SET DEFAULT 'active';
      ALTER TABLE rpg_club_admin_wizard_sessions
        ADD CONSTRAINT #{CHECK_CONSTRAINT}
        CHECK (status IN ('active', 'completed', 'cancelled'));
    SQL

    add_index TABLE, %i[command_key owner_user_id channel_id],
      unique: true,
      where: "status = 'active'",
      name: PARTIAL_INDEX
  end

  def down
    return unless table_exists?(TABLE)

    remove_index TABLE, name: PARTIAL_INDEX, if_exists: true

    execute <<~SQL
      ALTER TABLE rpg_club_admin_wizard_sessions
        DROP CONSTRAINT IF EXISTS #{CHECK_CONSTRAINT};
      UPDATE rpg_club_admin_wizard_sessions
      SET status = UPPER(status)
      WHERE status IN ('active', 'completed', 'cancelled');
      ALTER TABLE rpg_club_admin_wizard_sessions
        ALTER COLUMN status SET DEFAULT 'ACTIVE';
      ALTER TABLE rpg_club_admin_wizard_sessions
        ADD CONSTRAINT #{CHECK_CONSTRAINT}
        CHECK (status IN ('ACTIVE', 'COMPLETED', 'CANCELLED'));
    SQL

    add_index TABLE, %i[command_key owner_user_id channel_id],
      unique: true,
      where: "status = 'ACTIVE'",
      name: PARTIAL_INDEX
  end
end
