# frozen_string_literal: true

# Standardized `index`/`show` actions for the IGDB-curated taxonomy master
# tables (genres, themes, perspectives, modes, franchises, companies), plus an
# optional upsert-by-IGDB-id `create`.
#
# Each of these models is a controlled vocabulary with a `name` column and a
# custom primary key, and the endpoints they back are identical apart from the
# model and its serializer. A controller `include TaxonomyEndpoints` and calls
# `serves_taxonomy` instead of repeating six near-identical controllers.
#
#   class Api::V1::GenresController < ApplicationController
#     include TaxonomyEndpoints
#     serves_taxonomy GamedbGenre, resource: GenreResource, igdb_id_column: :igdb_genre_id
#   end
#
# `index` lists every record ordered by `name`, with an optional `?q`
# case-insensitive ILIKE-on-`name` filter, paginated via `render_collection`
# (ApplicationController). `show` returns a single record by primary key and
# 404s when it is missing (handled by the global RecordNotFound rescue).
#
# When `igdb_id_column` is given, a `create` action is defined too: an
# admin/service-only find-or-create keyed on that IGDB-id column, mirroring the
# bot's `ensureGenre`/`ensureTheme`/… (`getOrInsertMetadata`) helpers — it
# returns the existing row (200) when the IGDB id is already known and creates a
# new one (201) otherwise, so the bot's "check then insert" calls become a
# single request. Tables with no IGDB id to upsert on (companies) omit the
# argument and stay read-only.
module TaxonomyEndpoints
  extend ActiveSupport::Concern

  class_methods do
    # @param model [Class] an ActiveRecord master-table model with a `name` column
    # @param resource [Class] the Alba resource used to serialize it
    # @param igdb_id_column [Symbol, nil] the unique IGDB-id column to upsert on;
    #   omit to leave the table read-only (no `create` action)
    def serves_taxonomy(model, resource:, igdb_id_column: nil)
      define_method(:index) do
        scope = model.all
        scope = scope.where("name ILIKE ?", "%#{taxonomy_query}%") if params[:q].present?

        render_collection(scope, resource: resource, default_order: { name: :asc })
      end

      define_method(:show) do
        render json: { data: resource.new(model.find(params[:id])).serializable_hash }
      end

      return if igdb_id_column.nil?

      define_method(:create) do
        return unless require_admin_or_service!

        upsert_taxonomy(model, resource, igdb_id_column)
      end
    end
  end

  private

  def taxonomy_query
    ActiveRecord::Base.sanitize_sql_like(params[:q].to_s.strip)
  end

  # Find-or-create `model` keyed on `igdb_id_column`, taking `name` (and the
  # IGDB id) from the `data` envelope. The IGDB id is the upsert key and is
  # required; `name` is applied only when a new row is created (an existing row
  # keeps its name, matching the bot's ensure-helpers). 201 on create, 200 when
  # the IGDB id was already known.
  def upsert_taxonomy(model, resource, igdb_id_column)
    data = request_data
    igdb_id = data[igdb_id_column.to_s].presence
    return render(json: { error: "#{igdb_id_column} is required" }, status: :unprocessable_entity) if igdb_id.blank?

    record = model
      .create_with(name: data["name"])
      .find_or_create_by!(igdb_id_column => igdb_id)

    render json: { data: resource.new(record).serializable_hash },
      status: record.previously_new_record? ? :created : :ok
  end
end
