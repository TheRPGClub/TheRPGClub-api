# frozen_string_literal: true

module Api
  module V1
    module Codex
      # Club Lore (GLOSSARY.md, "Lore Entry"; spec #397, ticket #407). Members
      # list and read Lore Entries; Regulars and above publish them at once;
      # the author or a Moderator and above edits or deletes one
      # (ClubCodex::Actor). Gated by the `club_codex` Feature. The website
      # writes them; the bot only reads, acting for the member it names
      # (CodexActing).
      class LoreEntriesController < BaseController
        WRITES = %i[create update destroy].freeze
        TEXT_FIELDS = %w[title body occurred_on date_precision].freeze
        JSON_FIELDS = %w[rich_body].freeze

        before_action :require_acting_member!, only: WRITES

        # GET /api/v1/codex/lore_entries?page=&per=
        #
        # Newest first.
        def index
          render_entries(entries)
        end

        # GET /api/v1/codex/lore_entries/:id
        def show
          render_entry(find_entry)
        end

        # POST /api/v1/codex/lore_entries
        # Body: { "data": { "title", "rich_body", "body", "occurred_on", "date_precision" } }
        #
        # `rich_body` is the Plate.js story, stored as given; `body` is the
        # Discord markdown the website made from it. The date is optional;
        # a `month` or `year` one is moved to the start of its period
        # (CodexEntry::Dated).
        def create
          return forbid(ClubCodex::Refusals::CREATE) unless actor.can_create?(part)

          attributes = entry_fields
          return if performed?

          entry = CodexEntry.create!(attributes.merge(part: part, author_user_id: actor.user_id))
          render_entry(entry, status: :created)
        end

        # PATCH /api/v1/codex/lore_entries/:id
        # Body: { "data": { any of the fields create takes } }
        #
        # Changes only the fields given; a null date and precision removes
        # the date.
        def update
          entry = find_entry
          return forbid(ClubCodex::Refusals::EDIT) unless actor.can_edit?(entry)

          attributes = entry_fields
          return if performed?

          entry.update!(attributes)
          render_entry(entry)
        end

        # DELETE /api/v1/codex/lore_entries/:id
        #
        # A hard delete; its mentions go with it.
        def destroy
          destroy_entry(find_entry)
        end

        private

        def part = CodexEntry::LORE_ENTRY

        # The Lore Entry fields the request gives; 422 for a field it doesn't
        # take (a History Event Kind) or one that isn't text.
        def entry_fields = entry_attributes(request_data, text: TEXT_FIELDS, json: JSON_FIELDS)
      end
    end
  end
end
