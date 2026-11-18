# frozen_string_literal: true

module Api
  module V1
    module Codex
      # "See also" links between Club Codex entries of any part (spec #397,
      # ticket #409; ClubCodex::Links). A link belongs to both entries and
      # shows on both.
      #
      # The bot acts for the member it names (CodexActing):
      # `data.acting_user_id`.
      class EntryLinksController < BaseController
        before_action :require_acting_member!

        # PUT /api/v1/codex/entries/:id/links
        # Body: { "data": { "entry_ids": [1, 2] } }
        #
        # Replaces the entry's links with links to `entry_ids` (an empty list
        # removes them all). Whoever can edit the entry may, so a link to an
        # entry they can't edit can still be removed from this side.
        # Returns the entry.
        def update
          entry = CodexEntry.find(params[:id])
          return forbid(edit_refusal(entry)) unless actor.can_edit?(entry)

          ClubCodex::Links.replace!(entry, request_data["entry_ids"])
          render_entry(entry)
        rescue ClubCodex::Links::Invalid => error
          render json: { error: "invalid_links", message: error.message }, status: :unprocessable_content
        end
      end
    end
  end
end
