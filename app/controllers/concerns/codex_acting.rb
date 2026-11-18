# frozen_string_literal: true

# The member acting on the Club Codex, signed in or through the bot (spec
# #397), as a ClubCodex::Actor.
#
# The bot acts for a Discord user with the service token and names them
# (`acting_user_id`: a query parameter on reads and deletes, which carry no
# body, and `data.acting_user_id` on other writes); the API then decides from
# that member's stored roles, and applies the Feature Flag to them, since the
# service passes the feature gate (docs/adr/0005). `require_acting_member!`
# is the `before_action` for writes: 401 signed out, 400 without an acting
# member, 403 `feature_unavailable` when the Flag hides the Feature from
# them. A bot read without one is answered as for any member, with no rights
# in `viewer`, as is a signed-out Visitor where an endpoint lets one in (Club
# History).
module CodexActing
  extend ActiveSupport::Concern
  include ActingMember

  private

  def actor
    @actor ||=
      if current_principal.nil?
        ClubCodex::Actor.visitor
      elsif current_principal.service?
        member = acting_member
        ClubCodex::Actor.new(user_id: acting_user_id, regular: member&.role_regular? ? true : false,
          moderator: member&.moderator_or_above? ? true : false, admin: member&.admin_or_above? ? true : false)
      else
        ClubCodex::Actor.new(user_id: current_principal.id.to_s, regular: regular_role?,
          moderator: moderator_or_above?, admin: admin_or_above?)
      end
  end

  def acting_user_id
    return @acting_user_id if defined?(@acting_user_id)
    return super unless current_principal&.service? && request.delete?

    @acting_user_id = params[:acting_user_id].presence&.to_s
  end

  # A signed-out caller has no acting member: 401, as for any sign-in gate.
  def require_acting_member!
    return render(json: { error: "unauthorized" }, status: :unauthorized) if current_principal.nil?
    return true unless current_principal.service?
    return render(json: { error: "acting_user_id required" }, status: :bad_request) if acting_user_id.blank?
    return true if Features::Access.for_member(acting_member).can_use?(feature_key)

    render json: { error: "feature_unavailable" }, status: :forbidden
  end
end
