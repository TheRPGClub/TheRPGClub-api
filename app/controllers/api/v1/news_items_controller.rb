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

      # The stamp answers anyone, unchecked, so its poll never reaches
      # Postgres (a session or Feature Flag read would).
      skip_before_action :require_authentication!, only: :stamp
      feature :news_hub, except: :stamp

      before_action :require_service!, only: %i[uncopied update change_category destroy]

      # News Items per shelf on the Shelves tab: the default and the most.
      SHELF_PER = 10
      SHELF_MAX_PER = 20

      # GET /api/v1/news_items?category=releases,industry&q=zelda&page=1&per=50
      #
      # The News Items that have a News Category, newest first. `category`
      # narrows to those News Categories (comma-separated, or repeated as
      # `category[]`); an unknown key is a 400. Without it, the member's
      # default view: every News Category but the ones they switched off
      # (News Category Preferences, ticket #357). `q` searches link title and
      # comment. `since` and `until` (ISO 8601; a bad value is a 400) bound
      # posted_at: after `since`, at or before `until` (ticket api#496), so
      # the Catch-up view lists the new News Items with `since` set to the
      # News Mark and the seen ones with `until`. `meta` adds
      # `category_counts` and `hidden_categories` for the page's category
      # rail, and the member's `news_mark` with `new_count` and
      # `new_category_counts`: the News Items in the same view (categories
      # and `q`, not `since`/`until`) posted after the News Mark.
      #
      # An image whose Discord address has expired is served as unavailable,
      # and the bot is asked to renew it (NewsHub::BotJobs). The bot's own
      # reads (its catch-up lists the News Categories through the feed) ask
      # for nothing.
      def index
        categories = category_filter
        return if performed?

        bounds = posted_bounds
        return if performed?

        searched = search(NewsItem.listed)
        hidden = switched_off_categories
        view = searched
        view = view.where(category_key: categories) if categories.any?
        view = view.where.not(category_key: hidden) if categories.empty? && hidden.any?
        scope = view
        scope = scope.where("news_items.posted_at > ?", bounds[:since]) if bounds[:since]
        scope = scope.where(posted_at: ..bounds[:until]) if bounds[:until]
        pagy, items = pagy(scope.order(posted_at: :desc, id: :desc), **pagy_options)
        items = items.to_a
        now = Time.current
        NewsHub::BotJobs.renew_expired_images!(items, now: now) unless current_principal.service?

        render json: {
          data: news_item_json(items, now: now),
          meta: pagy_meta(pagy).merge(category_counts: category_counts(searched), hidden_categories: hidden,
            **new_counts(view))
        }
      end

      # GET /api/v1/news_items/stamp
      #
      # The News Feed Stamp (NewsItem::FeedStamp): changes whenever a News
      # Item is recorded, changed or removed. An open News page polls it and
      # reloads the feed when it changes. Read from a machine-local file, not
      # Postgres, so the poll lets Neon sleep; it tells nothing but that
      # something changed.
      def stamp
        response.headers["Cache-Control"] = "no-store"
        render json: { data: { stamp: NewsItem::FeedStamp.read.to_s } }
      end

      # GET /api/v1/news_items/shelves?per=10
      #
      # The Shelves tab (ticket api#497): for each News Category in the
      # member's default view, in News Category order, its newest `per` News
      # Items (default 10, at most 20) as the feed serves them, and how many
      # were posted today (UTC). The switched-off News Categories are left
      # out and listed in `meta.hidden_categories`. Expired images are
      # renewed as the feed renews them.
      def shelves
        hidden = switched_off_categories
        keys = NewsCategory.keys - hidden
        per = clamp_per(params[:per], default_per: SHELF_PER, max_per: SHELF_MAX_PER)
        now = Time.current
        shelved = NewsItem.newest_by_category(keys, per: per)
        items = shelved.values.flatten
        NewsHub::BotJobs.renew_expired_images!(items, now: now) unless current_principal.service?

        render json: {
          data: shelves_json(shelved, NewsItem.posted_today_by_category(keys, now: now), items, now: now),
          meta: { per: per, hidden_categories: hidden }
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

      # One shelf per News Category of `shelved` ({ key => items }), in
      # order, with its today count; the authors of every shelved item are
      # looked up once.
      def shelves_json(shelved, today_counts, items, now:)
        authors = NewsItemResource.authors_for(items)
        names = NewsCategory.all.to_h { |category| [ category.key, category.name ] }
        shelved.map do |key, shelf_items|
          { category_key: key, name: names.fetch(key), today_count: today_counts.fetch(key),
            items: NewsItemResource.new(shelf_items, params: { authors: authors, now: now }).serializable_hash }
        end
      end

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

      # The signed-in member's News Mark and how many News Items in `view`
      # were posted after it, per News Category (every key, in order) in one
      # grouped query. No News Mark (and the service token) counts nothing.
      def new_counts(view)
        mark = current_principal.discord_user? ? NewsMark.for(current_principal.id) : nil
        counts = mark ? view.where("news_items.posted_at > ?", mark).group(:category_key).count : {}
        by_category = NewsCategory.keys.index_with { |key| counts.fetch(key, 0) }
        { news_mark: mark&.utc&.iso8601(6), new_count: by_category.values.sum, new_category_counts: by_category }
      end

      # The `since` and `until` instants (nil when blank). Renders 400 for a
      # value that is not an ISO 8601 instant.
      def posted_bounds
        %i[since until].index_with do |name|
          value = params[name].to_s.strip
          next if value.empty?

          Time.iso8601(value)
        rescue ArgumentError
          render(json: { error: "#{name} must be an ISO 8601 instant" }, status: :bad_request)
          return {}
        end
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
