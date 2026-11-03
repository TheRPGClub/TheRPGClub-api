# frozen_string_literal: true

module Api
  module V1
    class SearchSynonymGroupsController < ApplicationController
      def index
        scope = GamedbSearchSynonymGroup.all
        # Text search across groups (#108): a group matches when any of its terms
        # matches `q` by literal text (case-insensitive) or normalised key.
        scope = scope.where(group_id: matching_group_ids(params[:q])) if params[:q].present?
        scope = scope.preload(:synonyms) if include_terms?
        render_collection(
          scope,
          resource: SearchSynonymGroupResource,
          default_order: { group_id: :asc },
          params: { include_terms: include_terms? }
        )
      end

      def show
        scope = include_terms? ? GamedbSearchSynonymGroup.preload(:synonyms) : GamedbSearchSynonymGroup
        render_group(scope.find(params[:id]), include_terms: include_terms?)
      end

      def create
        return unless require_admin_or_service!

        record = GamedbSearchSynonymGroup.create!(request_data)
        render json: { data: SearchSynonymGroupResource.new(record).serializable_hash }, status: :created
      end

      def update
        return unless require_admin_or_service!

        record = GamedbSearchSynonymGroup.find(params[:id])
        record.update!(request_data)
        render json: { data: SearchSynonymGroupResource.new(record).serializable_hash }
      end

      def destroy
        return unless require_admin_or_service!

        GamedbSearchSynonymGroup.find(params[:id]).destroy!
        render json: { deleted: true }
      end

      # Bulk-delete every term in the group, keeping the group itself (#108). Used
      # by the bot to atomically replace a group's terms (delete all, re-insert).
      def destroy_terms
        return unless require_admin_or_service!

        group = GamedbSearchSynonymGroup.find(params[:id])
        count = group.synonyms.delete_all
        render json: { deleted: true, count: count }
      end

      # Replace all of the group's terms in one transaction (#333). Admin and
      # up, or the bot. A signed-in member is recorded as the terms' creator;
      # only the bot may name one in the body.
      def replace_terms
        return unless require_admin_or_service!

        group = GamedbSearchSynonymGroup.find(params[:id])
        data = params.require(:data)
        created_by = current_principal.service? ? data[:created_by]&.to_s : current_principal.id.to_s
        group.replace_terms!(data.to_unsafe_h["terms"], created_by: created_by)
        render_group(GamedbSearchSynonymGroup.preload(:synonyms).find(group.group_id), include_terms: true)
      rescue GamedbSearchSynonymGroup::InvalidTerms => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      private

      # `?include=terms` embeds each group's terms (#333), so the site can list
      # groups with their terms in one request.
      def include_terms?
        params[:include].to_s.split(",").map(&:strip).include?("terms")
      end

      def render_group(group, include_terms: false, status: :ok)
        render json: {
          data: SearchSynonymGroupResource.new(group, params: { include_terms: include_terms }).serializable_hash
        }, status: status
      end

      def matching_group_ids(query)
        text = "%#{sanitize_like(query)}%"
        norm = "%#{sanitize_like(GamedbSearchSynonym.normalize_term(query))}%"
        GamedbSearchSynonym
          .where("term_text ILIKE :text OR term_norm LIKE :norm", text: text, norm: norm)
          .select(:group_id)
      end

      def sanitize_like(value)
        ActiveRecord::Base.sanitize_sql_like(value.to_s.strip)
      end
    end
  end
end
