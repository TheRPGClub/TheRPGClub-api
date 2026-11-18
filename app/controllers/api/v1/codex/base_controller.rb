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

        # The fields of `data` that are not the entry's: the bot's
        # `acting_user_id`.
        ACTING_FIELDS = %w[acting_user_id].freeze

        feature :club_codex

        rescue_from ActiveRecord::RecordInvalid do |error|
          render json: { error: "invalid_entry", message: error.record.errors.full_messages.to_sentence },
            status: :unprocessable_content
        end
        # Image storage (ticket #410), as for game images.
        rescue_from Backblaze::Client::ConfigurationError do |error|
          render json: { error: "backblaze_not_configured", message: error.message }, status: :unprocessable_content
        end
        rescue_from Backblaze::Client::RequestError do |error|
          render json: { error: "backblaze_request_failed", message: error.message }, status: :bad_gateway
        end

        private

        def entries = CodexEntry.where(part: part)

        def find_entry = entries.find(params[:id])

        # Paginated, newest first unless the part orders otherwise.
        def render_entries(scope, order: { created_at: :desc, id: :desc })
          render_collection(CodexEntryResource.preloaded(scope), resource: CodexEntryResource,
            default_order: order, params: { actor: actor },
            prepare: ->(page) { { mentions: ClubCodex::Mentions.of(page), links: ClubCodex::Links.of(page, actor: actor) } })
        end

        def render_entry(entry, status: :ok)
          render json: { data: entry_payload(entry) }, status: status
        end

        # The entry as every Club Codex endpoint shows it, for the acting
        # member, outside any envelope.
        def entry_payload(entry)
          entry = CodexEntryResource.preloaded(CodexEntry.where(id: entry.id)).first!
          CodexEntryResource.new(entry, params: { actor: actor }).serializable_hash
        end

        # Removes the entry's image files, then the entry. The files go first,
        # outside any lock, so a storage failure keeps the entry for a retry;
        # then, with the entry locked, any image an upload recorded meanwhile
        # goes too, so no file outlives its entry (an upload still on its way
        # finds the entry gone and removes its own file, ClubCodex::Images).
        def destroy_entry(entry, refusal: ClubCodex::Refusals::DELETE)
          return forbid(refusal) unless actor.can_delete?(entry)

          images = ClubCodex::Images.new
          images.remove_all!(entry)
          CodexEntry.transaction do
            entry.lock!
            images.remove_all!(entry)
            entry.destroy!
          end
          render json: { data: { id: entry.id, deleted: true } }
        end

        # The refusal for someone who may not edit `entry`.
        def edit_refusal(entry) = entry.history_event? ? ClubCodex::Refusals::HISTORY : ClubCodex::Refusals::EDIT

        # The entry fields `data` gives, as attributes: each of `text` must be
        # text or null; each of `json` (Plate content) is taken as given. A
        # field the part doesn't take, or a NUL character (which Postgres
        # can't store), is refused with 422 and nil is returned. Fields left
        # out stay out, so an edit changes only what it names.
        def entry_attributes(data, text:, json: [])
          extra = data.keys - text - json - ACTING_FIELDS
          return refuse_entry("A #{CodexEntry::PART_NAMES.fetch(part)} doesn't take #{extra.first}") if extra.any?

          (json + text).each_with_object({}) do |field, attributes|
            next unless data.key?(field)

            value = data[field]
            return refuse_entry("#{field} must be text") if text.include?(field) && !(value.nil? || value.is_a?(String))
            return refuse_entry("#{field} can't hold NUL characters") if nul?(value)

            attributes[field] = value
          end
        end

        # Whether `value`, or any text inside it, holds a NUL character.
        def nul?(value)
          case value
          when String then value.include?("\u0000")
          when Hash then value.any? { |key, item| nul?(key) || nul?(item) }
          when Array then value.any? { |item| nul?(item) }
          else false
          end
        end

        # 422 `invalid_entry`; nil, so a caller can return it as "no attributes".
        def refuse_entry(message)
          render json: { error: "invalid_entry", message: message }, status: :unprocessable_content
          nil
        end

        # 400 `error` for a filter whose value isn't one of `choices`.
        def refuse_choice(error, label, choices)
          render json: { error: error, message: "#{label} must be one of #{choices.join(', ')}" }, status: :bad_request
        end

        def forbid(message)
          render json: { error: "forbidden", message: message }, status: :forbidden
        end
      end
    end
  end
end
