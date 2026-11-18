# frozen_string_literal: true

module Api
  module V1
    module Codex
      # Club History (GLOSSARY.md, "Club History"; spec #397, ticket #408):
      # History Events in date order. Anyone reads them, Visitors included,
      # so the reads need no sign-in; the feature gate treats a signed-out
      # caller like any non-staff member, who finds the Feature only when
      # Live. Admins and Superadmins add, edit and delete any History Event
      # (ClubCodex::Actor).
      #
      # The bot acts for the member it names (CodexActing), as for Fun Facts.
      class HistoryEventsController < BaseController
        READS = %i[index show].freeze
        WRITES = %i[create update destroy].freeze
        TEXT_FIELDS = %w[title body occurred_on date_precision kind].freeze
        # `rich_body` is Plate content, stored as given.
        FIELDS = [ *TEXT_FIELDS, "rich_body" ].freeze

        skip_before_action :require_authentication!, only: READS
        before_action :require_acting_member!, only: WRITES

        # GET /api/v1/codex/history_events?kind=&page=&per=
        #
        # By date, then id. `kind` keeps one History Event Kind.
        def index
          scope = entries
          if params[:kind].present?
            return refuse_kind unless CodexEntry::KINDS.include?(params[:kind])

            scope = scope.where(kind: params[:kind])
          end

          render_entries(scope, order: { occurred_on: :asc, id: :asc })
        end

        # GET /api/v1/codex/history_events/:id
        def show
          render_entry(find_entry)
        end

        # POST /api/v1/codex/history_events
        # Body: { "data": { "title", "occurred_on", "date_precision", "kind",
        #                    "rich_body", "body" } }
        def create
          return forbid(ClubCodex::Refusals::HISTORY) unless actor.can_create?(part)

          fields = entry_fields
          return if performed?

          entry = CodexEntry.create!(fields.merge(part: part, author_user_id: actor.user_id))
          render_entry(entry, status: :created)
        end

        # PATCH /api/v1/codex/history_events/:id
        #
        # Changes only the fields given; the author stays.
        def update
          entry = find_entry
          return forbid(ClubCodex::Refusals::HISTORY) unless actor.can_edit?(entry)

          fields = entry_fields
          return if performed?

          entry.update!(fields)
          render_entry(entry)
        end

        # DELETE /api/v1/codex/history_events/:id
        def destroy
          destroy_entry(find_entry, refusal: ClubCodex::Refusals::HISTORY)
        end

        private

        def part = "history_event"

        # The History Event fields the request gives (text fields as text);
        # renders 422 and returns nil when one isn't.
        def entry_fields
          data = request_data
          TEXT_FIELDS.each do |field|
            text_field(data, field)
            return nil if performed?
          end
          data.slice(*FIELDS)
        end

        def refuse_kind
          render json: { error: "invalid_kind", message: "Kind must be one of #{CodexEntry::KINDS.join(', ')}" },
            status: :bad_request
        end
      end
    end
  end
end
