# frozen_string_literal: true

module Api
  module V1
    # News Items (spec #355, ticket #356). The bot records and removes them
    # with the service token as members post, edit and delete messages in the
    # News Channel, reports where each News Copy lives, and lists the News
    # Items still without one (ticket #368), and changes a News Item's News
    # Category for its author or staff (ticket #369); members read them as a
    # feed.
    # Gated by the News Hub Feature (the service token is never stopped by
    # the gate).
    class NewsItemsController < ApplicationController
      include ActingMember

      feature :news_hub

      before_action :require_service!, only: %i[uncopied update change_category destroy]

      # GET /api/v1/news_items?category=releases,industry&q=zelda&page=1&per=50
      #
      # The News Items that have a News Category, newest first. `category`
      # narrows to those News Categories (comma-separated, or repeated as
      # `category[]`); an unknown key is a 400. Without it, the member's
      # default view: every News Category but the ones they switched off
      # (News Category Preferences, ticket #357). `q` searches link title and
      # comment. `meta` adds `category_counts` and `hidden_categories` for the
      # page's category rail.
      #
      # An image whose Discord address has expired is served as unavailable,
      # and the bot is asked to renew it (NewsHub::BotJobs). The bot's own
      # reads (its catch-up lists the News Categories through the feed) ask
      # for nothing.
      def index
        categories = category_filter
        return if performed?

        searched = search(NewsItem.listed)
        hidden = switched_off_categories
        scope = searched
        scope = scope.where(category_key: categories) if categories.any?
        scope = scope.where.not(category_key: hidden) if categories.empty? && hidden.any?
        pagy, items = pagy(scope.order(posted_at: :desc, id: :desc), **pagy_options)
        items = items.to_a
        now = Time.current
        NewsHub::BotJobs.renew_expired_images!(items, now: now) unless current_principal.service?

        render json: {
          data: news_item_json(items, now: now),
          meta: pagy_meta(pagy).merge(category_counts: category_counts(searched), hidden_categories: hidden)
        }
      end

      # GET /api/v1/news_items/uncopied?origin=live&page=1&per=50
      #
      # The News Items with a News Category but no News Copy, oldest first
      # by posting time: the bot's history copy and its retries of failed
      # copies work through them. Imported items staff have not sorted are
      # left out, since a News Copy goes in its News Category's thread.
      # `origin` (live or import) narrows to that origin, so catch-up can
      # retry live items alone; omitted, both. An unknown origin is a 422.
      def uncopied
        origin = params[:origin].presence&.to_s
        if origin && NewsItem::ORIGINS.exclude?(origin)
          return render(json: { error: "unknown origin: #{origin} (expected #{NewsItem::ORIGINS.join(' or ')})" },
            status: :unprocessable_content)
        end

        scope = NewsItem.uncopied
        scope = scope.where(origin: origin) if origin
        pagy, items = pagy(scope.order(posted_at: :asc, id: :asc), **pagy_options)
        items = items.to_a

        render json: { data: news_item_json(items), meta: pagy_meta(pagy) }
      end

      # PUT /api/v1/news_items/:message_id
      #
      # Records the message as a News Item (201) or updates the one already
      # recorded (200); a payload of only `news_copy` reports where the News
      # Copy of a recorded News Item lives (200, or 404 when none is
      # recorded). See NewsItem.record!.
      def update
        item, created = NewsItem.record!(params[:message_id], item_params)
        render json: { data: news_item_json(item) }, status: created ? :created : :ok
      end

      # PUT /api/v1/news_items/:message_id/category
      # Body: { "data": { "acting_user_id": "...", "category_key": "rumours" } }
      #
      # Changes the News Item's News Category for the member who used the
      # bot's "Change news category" (ticket #369): its author, or staff as
      # the News Import decides it. An imported News Item staff have not
      # sorted is staff's alone: its author may not give it a category. The service token passes the feature
      # gate, so the News Hub Feature Flag is applied here to the acting
      # member instead (docs/adr/0005): nobody while Off, staff while
      # Preview. See NewsItem#change_category!. `meta.changed` is false when
      # the item was already in that News Category, and nothing changed.
      def change_category
        return render(json: { error: "acting_user_id required" }, status: :bad_request) if acting_user_id.blank?
        unless Features::Access.for_member(acting_member).can_use?(feature_key)
          return render(json: { error: "feature_unavailable" }, status: :forbidden)
        end

        item = NewsItem.find_by!(message_id: params[:message_id].to_s)
        return unless gate_or_forbid(acting_member_staff? || (item.author_id == acting_user_id && !item.unsorted?))

        changed = item.change_category!(params.require(:data).require(:category_key), by: acting_user_id)
        previous = changed ? item.category_key_previously_was : item.category_key

        render json: { data: news_item_json(item), meta: { changed: changed, previous_category_key: previous } }
      end

      # DELETE /api/v1/news_items/:message_id
      #
      # Removes the News Item for good. 200 whether or not it was recorded,
      # so the bot never has to know what the API holds: `removed` says
      # whether there was one, and `news_copy` where its News Copy lives (or
      # null), so the bot can delete the copy without looking it up first.
      def destroy
        item = NewsItem.remove!(params[:message_id])
        render json: { data: { removed: !item.nil?, news_copy: item&.news_copy } }
      end

      private

      # The News Item, or a list of them, as the API serves it, with each
      # author's name; `options` adds serializer params (the feed's `now`).
      def news_item_json(items, **options)
        NewsItemResource.new(items, params: { authors: NewsItemResource.authors_for(Array(items)), **options })
          .serializable_hash
      end

      def item_params
        data = params.require(:data)
        raise ActionController::ParameterMissing, "data (object)" unless data.respond_to?(:permit)

        item = data.permit(:channel_id, :category_key, :picked_category_key, :author_id, :author_name, :comment,
          :posted_at, :edited_at, link: NewsItem::LINK_FIELDS, images: %i[url expires_at],
          news_copy: %i[message_id thread_id]).to_h
        # A null news_copy (the item has no News Copy) is not a permitted
        # object, so permit drops it; keep it.
        item["news_copy"] = nil if data.key?(:news_copy) && data[:news_copy].nil?
        item
      end

      # The News Categories the signed-in member switched off (their News
      # Category Preferences), which the default view leaves out. A requested
      # category is always returned, so a preference never blocks anything.
      # The service token has none.
      def switched_off_categories
        return [] unless current_principal.discord_user?

        MemberNewsCategoryPreference.hidden_keys(current_principal.id)
      end

      # How many News Items each News Category holds in `scope` (the search
      # alone, before the category filter and the preferences), keyed by every
      # News Category in order, so the page can show a count for each.
      def category_counts(scope)
        counts = scope.group(:category_key).count
        NewsCategory.keys.index_with { |key| counts.fetch(key, 0) }
      end

      # Narrows to the News Items whose link title or comment contains `q`,
      # ignoring case. A blank `q` searches nothing.
      def search(scope)
        text = params[:q].to_s.strip
        return scope if text.empty?

        scope.where("link_title ILIKE :q OR comment ILIKE :q", q: "%#{NewsItem.sanitize_sql_like(text)}%")
      end

      # The requested News Category keys; [] when none. Renders 400 and
      # returns [] for an unknown key.
      def category_filter
        keys = Array(params[:category]).flat_map { |value| value.to_s.split(",") }.map(&:strip).compact_blank.uniq
        unknown = keys - NewsCategory.keys
        return keys if unknown.empty?

        render json: { error: "unknown category: #{unknown.join(', ')}" }, status: :bad_request
        []
      end
    end
  end
end
