# frozen_string_literal: true

module Api
  module V1
    class RegionsController < ApplicationController
      def index
        scope = GamedbRegion.all
        # Exact lookup by internal region code (`Game.getRegionByCode`, #106),
        # e.g. `?code=NA`. Returns the paginated list shape (a single-element one)
        # so the index contract stays uniform.
        scope = scope.where(region_code: params[:code]) if params[:code].present?
        # Lookup by IGDB region id (`?igdb_id=...`, #106) against the internal
        # `igdb_region_id` column.
        scope = scope.where(igdb_region_id: params[:igdb_id]) if params[:igdb_id].present?

        render_collection(scope, resource: RegionResource, default_order: { region_name: :asc })
      end

      def show
        render json: { data: GamedbRegion.find(params[:id]).as_json }
      end

      # POST /api/v1/regions  { data: { code, name, igdb_id } }
      #
      # Admin/service-only find-or-create keyed on `igdb_region_id` (the bot's
      # `ensureRegion`). The bot's payload fields map onto the columns:
      # `code` -> region_code, `name` -> region_name, `igdb_id` -> igdb_region_id.
      # `code`/`name` apply only when a new row is created; an existing region
      # (matched on the IGDB id) is returned untouched. 201 on create, 200 when
      # the IGDB id was already known.
      def create
        return unless require_admin_or_service!

        data = request_data
        igdb_id = data["igdb_id"].presence
        return render(json: { error: "igdb_id is required" }, status: :unprocessable_entity) if igdb_id.blank?

        record = GamedbRegion
          .create_with(region_code: data["code"], region_name: data["name"])
          .find_or_create_by!(igdb_region_id: igdb_id)

        render json: { data: RegionResource.new(record).serializable_hash },
          status: record.previously_new_record? ? :created : :ok
      end
    end
  end
end
