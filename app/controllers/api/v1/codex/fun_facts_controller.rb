# frozen_string_literal: true

module Api
  module V1
    module Codex
      # Fun Facts (GLOSSARY.md, "Fun Fact"; spec #397, ticket #404). Members
      # list and read them; Regulars and above add them, published at once;
      # the author or a Moderator and above edits or deletes one
      # (ClubCodex::Actor). Gated by the `club_codex` Feature.
      #
      # The bot acts for the member it names (CodexActing): writes need
      # `data.acting_user_id` (a DELETE: `acting_user_id` in the query).
      class FunFactsController < BaseController
        WRITES = %i[create update destroy draw].freeze

        before_action :require_acting_member!, only: WRITES

        # GET /api/v1/codex/fun_facts?q=&editable=&page=&per=
        #
        # Newest first. `q` keeps those whose text matches
        # (ClubCodex::EntrySearch); `editable=true` keeps those the acting
        # member may edit: their own, or all for a Moderator and above (the
        # bot's autocomplete names the member with `acting_user_id`).
        def index
          scope = ClubCodex::EntrySearch.matching(entries, params[:q])
          if params[:editable] == "true"
            return render(json: { error: "acting_user_id required" }, status: :bad_request) if acting_user_id.blank?

            scope = actor.editable(scope)
          end

          render_entries(scope)
        end

        # GET /api/v1/codex/fun_facts/:id
        def show
          render_entry(find_entry)
        end

        # POST /api/v1/codex/fun_facts
        # Body: { "data": { "body": "..." } }
        #
        # `body` is the Fun Fact, up to 300 characters with its `<@id>`
        # mention tokens.
        def create
          return forbid(ClubCodex::Refusals::CREATE) unless actor.can_create?

          body = text_field(request_data, "body")
          return if performed?

          entry = CodexEntry.create!(part: part, body: body, author_user_id: actor.user_id)
          render_entry(entry, status: :created)
        end

        # PATCH /api/v1/codex/fun_facts/:id
        # Body: { "data": { "body": "..." } }
        #
        # Doesn't move the Fun Fact in the queue.
        def update
          entry = find_entry
          return forbid(ClubCodex::Refusals::EDIT) unless actor.can_edit?(entry)

          data = request_data
          body = text_field(data, "body")
          return if performed?

          entry.update!(body: body) if data.key?("body")
          render_entry(entry)
        end

        # DELETE /api/v1/codex/fun_facts/:id
        #
        # A hard delete; its mentions go with it.
        def destroy
          destroy_entry(find_entry)
        end

        # POST /api/v1/codex/fun_facts/draw
        #
        # The next Fun Fact in the queue (ClubCodex::FunFactQueue), marked
        # shown: `{ fun_fact: <entry> }`, or `{ fun_fact: null }` when there
        # are none. Members call it; the bot calls it for the member using
        # /funfact (`data.acting_user_id`).
        def draw
          entry = ClubCodex::FunFactQueue.draw!
          return render(json: { fun_fact: nil }) unless entry

          render json: { fun_fact: entry_payload(entry) }
        end

        private

        def part = "fun_fact"

        # The entry payload render_entry sends, outside its `data` envelope.
        def entry_payload(entry)
          entry = CodexEntryResource.preloaded(CodexEntry.where(id: entry.id)).first!
          CodexEntryResource.new(entry, params: { actor: actor }).serializable_hash
        end
      end
    end
  end
end
