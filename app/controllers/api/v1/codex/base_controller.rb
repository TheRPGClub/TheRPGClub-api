# frozen_string_literal: true

module Api
  module V1
    module Codex
      # What every Club Codex endpoint shares (spec #397): the `club_codex`
      # Feature, the acting member (CodexActing) and the entry payload
      # (CodexEntryResource). Each part's controller names its `part` and
      # its own rules.
      #
      # Refusals carry `{ error, message }`; `message` is written for
      # members (403 `forbidden`, 422 `invalid_entry`).
      class BaseController < ApplicationController
        include CodexActing

        feature :club_codex

        rescue_from ActiveRecord::RecordInvalid do |error|
          render json: { error: "invalid_entry", message: error.record.errors.full_messages.to_sentence },
            status: :unprocessable_content
        end

        private

        def entries = CodexEntry.where(part: part)

        def find_entry = entries.find(params[:id])

        # Paginated, newest first unless the part orders otherwise.
        def render_entries(scope, order: { created_at: :desc, id: :desc })
          render_collection(CodexEntryResource.preloaded(scope), resource: CodexEntryResource,
            default_order: order, params: { actor: actor },
            prepare: ->(page) { { mentions: ClubCodex::Mentions.of(page) } })
        end

        def render_entry(entry, status: :ok)
          entry = CodexEntryResource.preloaded(CodexEntry.where(id: entry.id)).first!
          render json: { data: CodexEntryResource.new(entry, params: { actor: actor }).serializable_hash },
            status: status
        end

        def destroy_entry(entry, refusal: ClubCodex::Refusals::DELETE)
          return forbid(refusal) unless actor.can_delete?(entry)

          entry.destroy!
          render json: { data: { id: entry.id, deleted: true } }
        end

        # A text field from the request: a String, or nil when left out.
        def text_field(data, field)
          value = data[field]
          return value if value.nil? || value.is_a?(String)

          render json: { error: "invalid_entry", message: "#{field} must be text" }, status: :unprocessable_content
          nil
        end

        def forbid(message)
          render json: { error: "forbidden", message: message }, status: :forbidden
        end
      end
    end
  end
end
