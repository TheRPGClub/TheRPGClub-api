# frozen_string_literal: true

module Api
  module V1
    # The News Import (GLOSSARY.md, "News Hub"; spec #355, ticket #359):
    # bringing the Game News Archive's history into the News Hub, hidden until
    # staff sort it.
    #
    # The bot's scan recorded the archive's messages as imported News Items;
    # it and its batch endpoint are gone (ticket #370). Staff work through
    # the bot: list the unsorted imported News Items (`unsorted`), assign
    # News Categories or remove items with `skip` (`assign`), and read the
    # counts (`status`). Each requires the acting member to be an Admin or
    # Superadmin, decided here from the acting member the bot names
    # (`acting_user_id`), as the Feature Flag endpoints do.
    #
    # The News Import works for Admins and Superadmins while the News Hub is
    # Preview or Live, and for nobody while it is Off (docs/adr/0005: Off
    # means nobody uses the Feature, staff included). The feature gate turns
    # signed-in callers away while Off; the service token is never gated, so
    # the bot refuses its /news-import commands itself while Off.
    class NewsImportController < ApplicationController
      feature :news_hub

      before_action :require_import_staff!

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

      # The member the request acts for, by Discord user id: the session's
      # member, or the bot's named acting user (a query parameter on reads,
      # `data.acting_user_id` on writes).
      def acting_user_id
        @acting_user_id ||=
          if current_principal.service?
            (request.get? ? params[:acting_user_id] : params.dig(:data, :acting_user_id)).presence&.to_s
          else
            current_principal.id.to_s
          end
      end

      # Admins and Superadmins only. The bot's service token is not enough:
      # the acting member's stored roles decide. (Whether the News Hub is Off
      # is the feature gate's call, and the bot's.)
      def require_import_staff!
        return require_admin_or_above! unless current_principal.service?
        return render(json: { error: "acting_user_id required" }, status: :bad_request) if acting_user_id.blank?

        gate_or_forbid(Features::Access.staff_member?(RpgClubUser.without_images.find_by(user_id: acting_user_id)))
      end

      def assignment_rows
        rows = params.require(:data).permit(rows: %i[message_id value])[:rows]
        raise ActionController::ParameterMissing, "data.rows (array)" unless rows.is_a?(Array)

        rows.map(&:to_h)
      end
    end
  end
end
