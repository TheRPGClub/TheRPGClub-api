# frozen_string_literal: true

module Api
  module V1
    module Codex
      # The Club Codex entry search, across all three parts (spec #397,
      # ticket #409): the website's "See also" link picker. It finds only
      # what the caller may read, so a Visitor (signed out) finds only
      # History Events, and only while the Feature is Live.
      class EntriesController < BaseController
        skip_before_action :require_authentication!, only: :index

        # GET /api/v1/codex/entries?q=&part=&page=&per=
        #
        # `q` matches titles and text (ClubCodex::EntrySearch); title matches
        # come first, then the newest. Without `q`, every entry, newest
        # first. `part` keeps one part. Each result is the short link shape,
        # `{ id, part, title }` (CodexEntryLinkResource).
        def index
          scope = actor.readable(CodexEntry.all)
          if params[:part].present?
            return refuse_choice("invalid_part", "Part", CodexEntry::PARTS) unless CodexEntry::PARTS.include?(params[:part])

            scope = scope.where(part: params[:part])
          end

          render_collection(ClubCodex::EntrySearch.matching(scope, params[:q]), resource: CodexEntryLinkResource,
            default_order: ClubCodex::EntrySearch.order(params[:q]),
            prepare: ->(page) { { names: ClubCodex::Links.mentioned_names(page.select(&:fun_fact?)) } })
        end
      end
    end
  end
end
