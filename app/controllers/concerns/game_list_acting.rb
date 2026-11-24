# frozen_string_literal: true

# The member acting on Game Lists, signed in or through the bot (spec
# api#442), as a GameLists::Actor.
#
# The bot acts for a Discord user with the service token and names them
# (`acting_user_id`: a query parameter on reads and deletes, which carry no
# body, and `data.acting_user_id` on other writes); the API then decides from
# that member's stored roles, and applies the Feature Flag to them, since the
# service passes the feature gate (docs/adr/0005). A bot read without one is
# answered as for a member who owns no lists. `require_acting_member!` is the
# `before_action` for writes: 400 without an acting member (or one with no
# stored record), 403
# `feature_unavailable` when the Flag hides the Feature from them.
module GameListActing
  extend ActiveSupport::Concern
  include ActingMember

  private

  def actor
    @actor ||=
      if current_principal.service?
        member = acting_member
        GameLists::Actor.new(user_id: member&.user_id, moderator: member&.moderator_or_above? ? true : false,
          admin: member&.admin_or_above? ? true : false)
      else
        GameLists::Actor.new(user_id: current_principal.id.to_s, moderator: moderator_or_above?,
          admin: admin_or_above?)
      end
  end

  def acting_user_id
    return @acting_user_id if defined?(@acting_user_id)
    return super unless current_principal.service? && request.delete?

    @acting_user_id = params[:acting_user_id].presence&.to_s
  end

  def require_acting_member!
    return true unless current_principal.service?
    return render(json: { error: "acting_user_id required" }, status: :bad_request) if acting_user_id.blank?
    return render(json: { error: "acting_user_id is not a member" }, status: :bad_request) if acting_member.nil?
    return true if Features::Access.for_member(acting_member).can_use?(feature_key)

    render json: { error: "feature_unavailable" }, status: :forbidden
  end

  def forbid(message)
    render json: { error: "forbidden", message: message }, status: :forbidden
  end
end
