# frozen_string_literal: true

class ApplicationController < ActionController::API
  before_action :require_authentication!

  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found
  rescue_from ActiveRecord::InvalidForeignKey, with: :render_unprocessable_entity
  rescue_from ActiveRecord::RecordInvalid, with: :render_unprocessable_entity
  rescue_from ActiveRecord::RecordNotSaved, with: :render_unprocessable_entity
  rescue_from ActionController::ParameterMissing, with: :render_bad_request

  private

  def current_principal
    @current_principal ||= warden.user || warden.authenticate(:api_token, :user_session_token, store: false)
  end

  def require_authentication!
    Rails.logger.debug "AUTH_HEADER: #{request.get_header('HTTP_AUTHORIZATION').inspect}"
    return if current_principal.present?

    render json: { error: "unauthorized" }, status: :unauthorized
  end

  def warden
    request.env["warden"]
  end

  def render_not_found(error)
    render json: { error: error.message.presence || "not_found" }, status: :not_found
  end

  def render_bad_request(error)
    render json: { error: error.message }, status: :bad_request
  end

  def render_unprocessable_entity(error)
    render json: { error: error.message }, status: :unprocessable_entity
  end

  def render_collection(scope, default_order:)
    records = scope.order(default_order).limit(pagination_limit).offset(pagination_offset)

    render json: {
      data: records.as_json,
      meta: {
        limit: pagination_limit,
        offset: pagination_offset
      }
    }
  end

  def request_data
    params.require(:data).permit!.to_h
  end

  def require_admin_or_service!
    return true if current_principal&.service?
    if current_principal&.discord_user?
      return true if current_principal.dev?
      return true if RpgClubUser.where(user_id: current_principal.id, role_admin: true).exists?
    end

    render json: { error: "forbidden" }, status: :forbidden
    false
  end

  def require_owner!
    owner_id = resolve_owner_id

    return true if current_principal&.service?
    return true if current_principal&.discord_user? && owner_id.present? && current_principal.id.to_s == owner_id.to_s

    render json: { error: "forbidden" }, status: :forbidden
    false
  end

  # Override in controllers that need a non-default lookup. Defaults to params[:user_id].
  def resolve_owner_id
    params[:user_id]
  end

  def pagination_limit(default: 50, max: 500)
    [ [ params.fetch(:limit, default).to_i, 1 ].max, max ].min
  end

  def pagination_offset
    return [ params[:offset].to_i, 0 ].max if params[:offset].present?

    page = [ params.fetch(:page, 1).to_i, 1 ].max
    (page - 1) * pagination_limit
  end
end
