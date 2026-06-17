# frozen_string_literal: true

module Api
  module V1
    # Seen-item tracking for RSS feeds, backing the GameDB bot's dedup loop
    # (#93). Replaces the bot's direct-SQL `getSeenItemHashes` / `markItemsSeen`
    # against `rpg_club_rss_feed_items`.
    class RssFeedItemsController < ApplicationController
      # GET /api/v1/rss_feeds/:rss_feed_id/items
      #
      # Given a candidate list of item hashes, returns just the ones already
      # recorded as seen for this feed, so the bot dedupes without fetching every
      # stored hash. The candidate list is read from `params[:hashes]`, which is
      # populated from either repeated `?hashes[]=` query params or a JSON body
      # `{ "hashes": [...] }` (preferred for large candidate lists). An empty or
      # absent list yields `{ "data": [] }`.
      def index
        feed = RpgClubRssFeed.find(params[:rss_feed_id])
        hashes = Array(params[:hashes]).map(&:to_s).reject(&:blank?).uniq
        seen = hashes.empty? ? [] : feed.items.where(item_id_hash: hashes).pluck(:item_id_hash)
        render json: { data: seen }
      end

      # POST /api/v1/rss_feeds/:rss_feed_id/items
      #
      # Bulk-marks items as seen with insert-or-ignore semantics on the
      # `(feed_id, item_id_hash)` primary key; entries whose hash is already
      # stored are skipped. Returns the number of rows actually inserted.
      def create
        feed = RpgClubRssFeed.find(params[:rss_feed_id])
        rows = item_rows(feed.feed_id)
        created = rows.empty? ? 0 : RpgClubRssFeedItem.insert_all(rows, returning: %w[item_id_hash]).count
        render json: { created: created }, status: :created
      end

      private

      # Build insert rows from the request body, scoped to this feed. Entries
      # without an `item_id_hash` are skipped, and the batch is de-duped on the
      # hash so a repeated value can't trip Postgres' `ON CONFLICT DO NOTHING`.
      def item_rows(feed_id)
        entries = params.permit(data: %i[item_id_hash title url published_at])[:data]
        Array(entries)
          .filter_map do |entry|
            hash = entry[:item_id_hash].presence
            next unless hash

            {
              feed_id: feed_id,
              item_id_hash: hash,
              title: entry[:title].presence,
              url: entry[:url].presence,
              published_at: entry[:published_at].presence
            }
          end
          .uniq { |row| row[:item_id_hash] }
      end
    end
  end
end
