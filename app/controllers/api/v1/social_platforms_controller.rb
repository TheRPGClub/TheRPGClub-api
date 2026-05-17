# frozen_string_literal: true

module Api
  module V1
    class SocialPlatformsController < ApplicationController
      def index
        render_collection(SocialPlatform.all, default_order: { position: :asc, label: :asc })
      end

      def create
        record = SocialPlatform.new(request_data.merge("created_by_user_id" => current_principal&.id))

        if record.save
          render json: { data: record.as_json }, status: :created
        else
          existing = duplicate_label_match(record)
          if existing
            render json: { data: existing.as_json }, status: :ok
          else
            render json: { error: record.errors.full_messages.to_sentence }, status: :unprocessable_entity
          end
        end
      end

      private

      def duplicate_label_match(record)
        return nil if record.label.blank?
        return nil unless record.errors.of_kind?(:label, :taken)

        SocialPlatform.where("LOWER(label) = ?", record.label.downcase).first
      end
    end
  end
end
