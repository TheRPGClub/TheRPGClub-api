# frozen_string_literal: true

# Who a GOTY Vote write is for (nominations, votes): a signed-in member acts
# only for themselves (a `user_id` may be left out or be their own); the
# service must name the member in `user_id`.
module ActsForMember
  extend ActiveSupport::Concern

  private

  # The member the write is for, or nil after rendering 422
  # `user_id_required` (service without a member), 404 (service naming an
  # unknown member) or 403 (a member acting for someone else).
  def acting_member_id(requested)
    requested = requested.to_s.presence
    if current_principal&.service?
      if requested.nil?
        render json: { error: "user_id_required", message: "the service must name the member in user_id" },
          status: :unprocessable_content
        return
      end
      return requested if RpgClubUser.exists?(user_id: requested)

      render json: { error: "not_found", message: "no member #{requested}" }, status: :not_found
      return
    end
    return current_principal.id.to_s if current_principal&.discord_user? && (requested.nil? || own?(requested))

    render json: { error: "forbidden" }, status: :forbidden
    nil
  end

  def own?(user_id)
    current_principal&.discord_user? && current_principal.id.to_s == user_id.to_s
  end
end
