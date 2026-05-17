# frozen_string_literal: true

# Discord role snowflake IDs for TheRPGClub guild.
# Role IDs aren't secret; commit them so all environments stay aligned.
# To find a role's ID: enable Discord Developer Mode, then right-click the
# role in Server Settings > Roles and choose "Copy Role ID".
module DiscordRoles
  DEV = "1500977607473103039"
  LONGSTANDING = "928752571462586369"

  def self.id_for(role)
    case role
    when :dev then DEV
    when :longstanding then LONGSTANDING
    end
  end
end
