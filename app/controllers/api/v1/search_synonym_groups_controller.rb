# frozen_string_literal: true

module Api
  module V1
    class SearchSynonymGroupsController < ApplicationController
      def index
        scope = GamedbSearchSynonymGroup.all
        # Text search across groups (#108): a group matches when any of its terms
        # matches `q` by literal text (case-insensitive) or normalised key.
        scope = scope.where(group_id: matching_group_ids(params[:q])) if params[:q].present?
        render_collection(scope, resource: SearchSynonymGroupResource, default_order: { group_id: :asc })
      end

      def show
        render json: { data: SearchSynonymGroupResource.new(GamedbSearchSynonymGroup.find(params[:id])).serializable_hash }
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

      private

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
