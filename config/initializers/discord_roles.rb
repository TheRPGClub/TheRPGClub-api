# frozen_string_literal: true

# Discord role snowflake IDs for TheRPGClub guild.
# Role IDs aren't secret; commit them so all environments stay aligned.
# To find a role's ID: enable Discord Developer Mode, then right-click the
# role in Server Settings > Roles and choose "Copy Role ID".
module DiscordRoles
  DEV = "1500977607473103039"
  LONGSTANDING = "928752571462586369"
  ADMIN = "461891227613265940"
  MODERATOR = "267881447258325002"
  REGULAR = "267883288817958912"
  MEMBER = "747520789003239530"

  # The rpg_club_users role flag columns that follow Discord role membership,
  # keyed to the role each one mirrors. `role_dev` (Superadmin) is stored so
  # the API can tell a Superadmin acting through the bot (spec #347); the
  # session token keeps its own `dev` flag for the session's staff gates.
  # Longstanding stays on the session token only.
  USER_FLAG_ROLES = {
    "role_dev" => DEV,
    "role_admin" => ADMIN,
    "role_moderator" => MODERATOR,
    "role_regular" => REGULAR,
    "role_member" => MEMBER
  }.freeze

  def self.id_for(role)
    case role
    when :dev then DEV
    when :longstanding then LONGSTANDING
    when :admin then ADMIN
    when :moderator then MODERATOR
    when :regular then REGULAR
    when :member then MEMBER
    end
  end

  # The role flag columns derived from a member's current Discord role IDs.
  def self.user_flags_for(role_ids)
    held = Array(role_ids).map(&:to_s)
    USER_FLAG_ROLES.transform_values { |role_id| held.include?(role_id) }
  end
end
