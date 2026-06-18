# frozen_string_literal: true

module Api
  module V1
    class SearchSynonymsController < ApplicationController
      def index
        scope = GamedbSearchSynonym.all
        scope = scope.where(group_id: params[:group_id]) if params[:group_id].present?
        # Exact-match lookup on the normalised key (#108): drives game-search
        # synonym expansion. The input is normalised the same way `term_norm` is
        # stored, so `ff7`, `FF7` and `FF-7` all match the `ff7` term.
        scope = scope.where(term_norm: GamedbSearchSynonym.normalize_term(params[:term])) if params[:term].present?
        # Free-text search across the flat term list (#108): matches the literal
        # text case-insensitively and the normalised key by substring.
        scope = text_search(scope, params[:q]) if params[:q].present?
        render_collection(scope, resource: SearchSynonymResource, default_order: { group_id: :asc, term_text: :asc })
      end

      def show
        render json: { data: GamedbSearchSynonym.find(params[:id]).as_json }
      end

      def create
        return unless require_admin_or_service!

        record = GamedbSearchSynonym.create!(request_data)
        render json: { data: record.as_json }, status: :created
      end

      def update
        return unless require_admin_or_service!

        record = GamedbSearchSynonym.find(params[:id])
        record.update!(request_data)
        render json: { data: record.as_json }
      end

      def destroy
        return unless require_admin_or_service!

        GamedbSearchSynonym.find(params[:id]).destroy!
        render json: { deleted: true }
      end

      private

      # `q` matches the literal term case-insensitively (`term_text`) OR the
      # normalised key by substring (`term_norm`), mirroring the bot's listSynonyms.
      def text_search(scope, query)
        text = "%#{sanitize_like(query)}%"
        norm = "%#{sanitize_like(GamedbSearchSynonym.normalize_term(query))}%"
        scope.where("term_text ILIKE :text OR term_norm LIKE :norm", text: text, norm: norm)
      end

      def sanitize_like(value)
        ActiveRecord::Base.sanitize_sql_like(value.to_s.strip)
      end
    end
  end
end
