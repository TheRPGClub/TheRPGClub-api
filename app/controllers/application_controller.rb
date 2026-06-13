# frozen_string_literal: true

class ApplicationController < ActionController::API
  include Pagy::Method

  # Default and ceiling page sizes for paginated collections.
  DEFAULT_PER = 50
  MAX_PER = 500

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

  # Render a paginated collection.
  #
  # When `resource` is given the records are serialized through that Alba
  # resource; otherwise they fall back to `as_json` (used by endpoints not yet
  # migrated to a resource). `params` is forwarded to the resource for
  # association/conditional injection.
  def render_collection(scope, resource: nil, default_order:, params: {}, default_per: DEFAULT_PER, max_per: MAX_PER)
    pagy, records = pagy(scope.order(default_order), **pagy_options(default_per:, max_per:))
    data = resource ? resource.new(records, params: params).serializable_hash : records.as_json

    render json: { data: data, meta: pagy_meta(pagy) }
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

  def require_service!
    return true if current_principal&.service?

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

  # Page-native pagination options for pagy, derived from the request params.
  #
  # Canonical params are `?page` and `?per`. We also accept the legacy
  # `?limit`/`?offset` pair (`limit` -> per, `offset` -> page) so the unaudited
  # Discord-bot consumer keeps working. The alias is transitional and should be
  # dropped once the bot is confirmed migrated to page/per.
  def pagy_options(default_per: DEFAULT_PER, max_per: MAX_PER)
    per = clamp_per(params[:per].presence || params[:limit], default_per:, max_per:)
    page =
      if params[:page].blank? && params[:offset].present?
        (params[:offset].to_i / per) + 1
      else
        params[:page].to_i
      end

    { page: [ page, 1 ].max, limit: per }
  end

  # Build page-native pagination meta from a pagy instance.
  def pagy_meta(pagy)
    {
      page: pagy.page,
      pages: pagy.pages,
      count: pagy.count,
      per: pagy.limit,
      prev: pagy.previous,
      next: pagy.next
    }
  end

  def clamp_per(value, default_per: DEFAULT_PER, max_per: MAX_PER)
    per = value.to_i
    per = default_per if per <= 0
    [ per, max_per ].min
  end
end
