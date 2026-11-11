# frozen_string_literal: true

module Api
  module V1
    # The News Import (GLOSSARY.md, "News Hub"; spec #355, ticket #359):
    # the messages posted in the News Channel before the News Hub launched,
    # brought in as imported News Items, hidden until staff sort them.
    #
    # Staff work through the bot: list the unsorted imported News Items
    # (`unsorted`), assign News Categories or remove items with `skip`
    # (`assign`), and read the counts (`status`). Each requires the acting
    # member to be an Admin or Superadmin, decided from the member the bot
    # names (`acting_user_id`), as the Feature Flag endpoints do
    # (ActingMember).
    #
    # The News Import works for Admins and Superadmins while the News Hub is
    # Preview or Live, and for nobody while it is Off (docs/adr/0005: Off
    # means nobody uses the Feature, staff included). The feature gate turns
    # signed-in callers away while Off; the service token is never gated, so
    # the bot refuses its /news-import commands itself while Off.
    class NewsImportController < ApplicationController
      include ActingMember

      feature :news_hub

      before_action :require_acting_staff!

      # GET /api/v1/news_import/items?acting_user_id=&page=&per=
      #
      # The imported News Items staff have not sorted, oldest first.
      def unsorted
        pagy, items = pagy(NewsItem.unsorted.order(posted_at: :asc, id: :asc), **pagy_options)
        items = items.to_a

        render json: {
          data: NewsImportItemResource.new(items, params: { authors: NewsItemResource.authors_for(items) })
            .serializable_hash,
          meta: pagy_meta(pagy)
        }
      end

      # POST /api/v1/news_import/assignments
      # Body: { "data": { "acting_user_id": "..." (bot only), "rows": [ { "message_id": "...", "value": "releases|skip" } ] } }
      def assign
        render json: { data: NewsImport::Assign.call(assignment_rows, by: acting_user_id) }
      rescue NewsImport::Assign::TooLarge => error
        render json: { error: error.message }, status: :unprocessable_content
      end

      # GET /api/v1/news_import/status?acting_user_id=
      def status
        render json: { data: NewsImport.status }
      end

      private

      def assignment_rows
        rows = params.require(:data).permit(rows: %i[message_id value])[:rows]
        raise ActionController::ParameterMissing, "data.rows (array)" unless rows.is_a?(Array)

        rows.map(&:to_h)
      end
    end
  end
end
