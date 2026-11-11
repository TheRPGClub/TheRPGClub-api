# frozen_string_literal: true

# The member a request acts for, and whether they are staff (docs/adr/0005).
#
# A signed-in member acts for themselves. The bot calls with the service
# token and names the Discord user it acts for (`acting_user_id`: a query
# parameter on reads, `data.acting_user_id` on writes); the API then decides
# from that member's stored roles, never from the token.
#
# `require_acting_staff!` is the `before_action` for endpoints only staff
# use (Feature Flags, the News Import): a signed-in caller must pass the
# Admin-or-above staff gate (StaffGates); the bot gets 400
# `acting_user_id required` without an acting member, and 403
# `{ error: "forbidden" }` unless that member is staff.
module ActingMember
  extend ActiveSupport::Concern

  private

  # The acting member's Discord user id; nil when the bot names none.
  def acting_user_id
    return @acting_user_id if defined?(@acting_user_id)

    @acting_user_id =
      if current_principal.service?
        source = request.get? ? params : params[:data]
        source[:acting_user_id].presence&.to_s if source.respond_to?(:permit)
      else
        current_principal.id.to_s
      end
  end

  # The acting member's stored record (nil when they have none).
  def acting_member
    return @acting_member if defined?(@acting_member)

    @acting_member = acting_user_id && RpgClubUser.without_images.find_by(user_id: acting_user_id)
  end

  # Whether the acting member is staff by their stored roles: Admin, or
  # Superadmin by the dev role.
  def acting_member_staff? = Features::Access.staff_member?(acting_member)

  def require_acting_staff!
    return require_admin_or_above! unless current_principal.service?
    return render(json: { error: "acting_user_id required" }, status: :bad_request) if acting_user_id.blank?

    gate_or_forbid(acting_member_staff?)
  end
end
