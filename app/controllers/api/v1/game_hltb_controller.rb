# frozen_string_literal: true

module Api
  module V1
    # On-demand HowLongToBeat lookups for a GameDB game (web parity 2), ported
    # from the bot's `/hltb`. Saved times are served without scraping; a fresh
    # scrape is saved only when the game's initial release is more than six
    # months ago, so early estimates for new releases do not stick.
    class GameHltbController < ApplicationController
      SAVE_AFTER = 6.months

      before_action :require_member_or_above!

      # POST /api/v1/games/:id/hltb/lookup
      #
      # 200 { data: Hltb, meta: { source: "cache"|"hltb", saved: bool } }.
      # 404 hltb_no_match, 502 hltb_lookup_failed, 503 hltb_not_configured.
      def lookup
        game = GamedbGame.find(params[:id])
        return render_hltb(game.hltb_cache, source: "cache", saved: true) if game.hltb_cache

        result = Hltb::Client.new.search(game.title)
        unless result
          return render json: { error: "hltb_no_match", message: "HowLongToBeat has no match for #{game.title}." },
            status: :not_found
        end

        cache = build_cache(game, result)
        saved = saveable?(game)
        cache.save! if saved
        render_hltb(cache, source: "hltb", saved:)
      rescue Hltb::Client::ConfigurationError => error
        render json: { error: "hltb_not_configured", message: error.message }, status: :service_unavailable
      rescue Hltb::Client::RequestError => error
        render json: { error: "hltb_lookup_failed", message: error.message }, status: :bad_gateway
      end

      private

      def saveable?(game)
        game.initial_release_date.present? && game.initial_release_date <= SAVE_AFTER.ago
      end

      # The scraped values as a cache row, trimmed to the column limits.
      def build_cache(game, result)
        attributes = result.to_h.except(:name, :url, :image_url).merge(
          hltb_name: result.name, hltb_url: result.url, hltb_image_url: result.image_url,
          source_query: game.title, scraped_at: Time.current
        )
        trimmed = attributes.to_h do |column, value|
          limit = RpgClubHltbCache.columns_hash.fetch(column.to_s).limit
          [ column, value && limit ? value.to_s.first(limit) : value ]
        end
        RpgClubHltbCache.new(gamedb_game_id: game.game_id, **trimmed)
      end

      def render_hltb(cache, source:, saved:)
        render json: { data: HltbResource.new(cache).serializable_hash, meta: { source:, saved: } }
      end
    end
  end
end
