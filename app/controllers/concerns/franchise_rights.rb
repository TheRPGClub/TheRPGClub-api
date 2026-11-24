# frozen_string_literal: true

# Who may change Franchises (spec api#442), shared by the Franchise and
# Franchise history controllers. Rights come from the acting member's stored
# roles (docs/adr/0005): the signed-in member, or the member the bot names in
# `acting_user_id` (the query on GET and DELETE, `data.` otherwise).
#
# - Editors (Regulars, or Moderator and above): link, unlink, Mainline,
#   create, the history and undo.
# - Admins and above also rename, merge and delete.
module FranchiseRights
  extend ActiveSupport::Concern
  include ActingMember

  EDIT_REFUSAL = "You need the Regulars role to change Franchises."
  ADMIN_REFUSAL = "You need to be an Admin to rename, merge or delete Franchises."

  private

  # A DELETE carries no body, so the bot names its member in the query.
  def acting_user_id
    return @acting_user_id if defined?(@acting_user_id)
    return super unless current_principal&.service? && request.delete?

    @acting_user_id = params[:acting_user_id].presence&.to_s
  end

  def can_edit?
    member_rights { |member| member.role_regular? || member.moderator_or_above? } ||
      (!current_principal.service? && regular_or_staff?)
  end

  def can_admin?
    member_rights(&:admin_or_above?) || (!current_principal.service? && admin_or_above?)
  end

  # For the bot, the named member's stored roles (false when it names
  # none); nil for a signed-in member, whose roles StaffGates reads.
  def member_rights
    return nil unless current_principal.service?

    acting_member ? (yield(acting_member) ? true : false) : false
  end

  # 400 for the bot without an acting member; 403 unless Regular or above.
  def require_editor! = require_franchise_right!(can_edit?, EDIT_REFUSAL)

  # 400 for the bot without an acting member; 403 unless Admin or above.
  def require_franchise_admin! = require_franchise_right!(can_admin?, ADMIN_REFUSAL)

  def require_franchise_right!(allowed, refusal)
    if current_principal.service? && acting_user_id.blank?
      render json: { error: "acting_user_id required" }, status: :bad_request
      return false
    end
    return true if allowed

    render json: { error: "forbidden", message: refusal }, status: :forbidden
    false
  end
end
