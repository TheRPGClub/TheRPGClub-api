# frozen_string_literal: true

# The member acting on Challenges and Runs, signed in or through the bot
# (spec #376), as a Challenges::Actor.
#
# The bot acts for a Discord user with the service token and names them
# (`acting_user_id`: a query parameter on reads and deletes, which carry no
# body, and `data.acting_user_id` on other writes); the API then decides from
# that member's stored roles, and applies the Feature Flag to them, since the
# service passes the feature gate (docs/adr/0005). `require_acting_member!`
# is the `before_action` for writes: 400 without an acting member, 403
# `feature_unavailable` when the Flag hides the Feature from them.
module ChallengeActing
  extend ActiveSupport::Concern
  include ActingMember

  private

  def actor
    @actor ||=
      if current_principal.service?
        member = acting_member
        Challenges::Actor.new(user_id: acting_user_id, regular: member&.role_regular? ? true : false,
          moderator: member&.moderator_or_above? ? true : false)
      else
        Challenges::Actor.new(user_id: current_principal.id.to_s, regular: regular_role?,
          moderator: moderator_or_above?)
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
    return true if Features::Access.for_member(acting_member).can_use?(feature_key)

    render json: { error: "feature_unavailable" }, status: :forbidden
  end

  def forbid(message)
    render json: { error: "forbidden", message: message }, status: :forbidden
  end

  # The Challenges the actor may see: hidden ones only for Moderators and
  # above and their Host.
  def visible_challenges
    return Challenge.all if actor.moderator_or_above?
    return Challenge.visible if actor.user_id.blank?

    Challenge.visible.or(Challenge.where(host_user_id: actor.user_id))
  end
end
