# frozen_string_literal: true

# Named role gates matching the Discord bot's role checks (web parity 2).
#
# Each gate has a predicate (for combining with other checks) and a
# rendering `require_*!` twin for `before_action`, which renders 403
# `{ error: "forbidden" }` and returns false on refusal.
#
#   member_role?          Members role
#   member_or_staff?      Members role, or Moderator and above
#   regular_role?         Regulars role
#   regular_or_staff?     Regulars role, or Moderator and above
#   moderator_or_above?   Moderator, Admin or Superadmin
#   admin_or_above?       Admin or Superadmin (admin_or_service? is an older name for it)
#   superadmin?           Superadmin (the session token's `dev` flag)
#   discord_user_or_service?  any signed-in Discord user, whatever their roles
#
# The service principal passes every gate: the bot runs its own role checks
# before acting for a member. Role flags are read from the member's record on
# each request, so a sign-in or a bot role report takes effect at once.
# Superadmin stays on the session token, as it was before these gates.
#
# The Members and Regulars gates check that one role only; an endpoint that
# should also admit staff combines them, e.g. `regular_role? || admin_or_above?`.
module StaffGates
  extend ActiveSupport::Concern

  ROLE_FLAGS = %i[role_admin role_moderator role_regular role_member].freeze

  private

  def member_role?
    current_principal&.service? || staff_flag?(:role_member)
  end

  # Bot commands open to "any member" (e.g. adding a game from IGDB): the
  # Members role, plus staff who may not hold it.
  def member_or_staff?
    member_role? || moderator_or_above?
  end

  def regular_role?
    current_principal&.service? || staff_flag?(:role_regular)
  end

  # Bot commands open to Regulars (e.g. linking a thread to a game), plus
  # staff who may not hold the role.
  def regular_or_staff?
    regular_role? || moderator_or_above?
  end

  def moderator_or_above?
    superadmin? || staff_flag?(:role_admin) || staff_flag?(:role_moderator)
  end

  def admin_or_above?
    superadmin? || staff_flag?(:role_admin)
  end

  def superadmin?
    return true if current_principal&.service?

    current_principal&.discord_user? && current_principal.dev? ? true : false
  end

  # Any signed-in Discord user, roles or not, plus the service: the same set of
  # callers the game key donate gate admits. For IGDB search and import, which
  # cannot tell a donation from any other use.
  def discord_user_or_service?
    current_principal&.service? || current_principal&.discord_user? ? true : false
  end

  def require_member_role!
    gate_or_forbid(member_role?)
  end

  def require_member_or_staff!
    gate_or_forbid(member_or_staff?)
  end

  def require_regular_role!
    gate_or_forbid(regular_role?)
  end

  def require_regular_or_staff!
    gate_or_forbid(regular_or_staff?)
  end

  def require_moderator_or_above!
    gate_or_forbid(moderator_or_above?)
  end

  def require_admin_or_above!
    gate_or_forbid(admin_or_above?)
  end

  def require_superadmin!
    gate_or_forbid(superadmin?)
  end

  def require_discord_user_or_service!
    gate_or_forbid(discord_user_or_service?)
  end

  def gate_or_forbid(allowed)
    return true if allowed

    render json: { error: "forbidden" }, status: :forbidden
    false
  end

  # The signed-in member's role flags, loaded once per request.
  def staff_flag?(flag)
    return false unless current_principal&.discord_user?

    @staff_flags ||= begin
      values = RpgClubUser.where(user_id: current_principal.id).pick(*ROLE_FLAGS)
      ROLE_FLAGS.zip(Array(values)).to_h
    end
    @staff_flags[flag] == true
  end
end
