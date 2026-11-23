# frozen_string_literal: true

module Api
  module V1
    # On-demand HowLongToBeat lookups for a GameDB game (web parity 2), ported
    # from the bot's `/hltb`. Saved times are served without scraping; a fresh
    # scrape is saved only when the game's initial release is more than six
    # months ago, so early estimates for new releases do not stick. A lookup
    # that is not saved (no match, or a recent or undated game) is kept in the
    # Rails cache for UNSAVED_TTL, so repeated lookups do not spend the Google
    # Custom Search quota.
    #
    # `force: true` searches again for a game whose times are saved and
    # overwrites them (spec api#437), at most once per
    # RpgClubHltbCache::FORCE_INTERVAL per game; Admins and above are exempt.
    # Inside the interval it answers 429 with the date the next one is
    # allowed. Without saved times, `force` changes nothing.
    class GameHltbController < ApplicationController
      feature :game_index

      SAVE_AFTER = 6.months
      UNSAVED_TTL = 1.day

      before_action :require_member_or_staff!

      # POST /api/v1/games/:id/hltb/lookup
      #
      # Body (optional): { force: true }.
      # 200 { data: Hltb, meta: { source: "cache"|"hltb", saved: bool } }.
      # 404 hltb_no_match, 429 hltb_search_too_soon, 502 hltb_lookup_failed,
      # 503 hltb_not_configured.
      def lookup
        game = GamedbGame.find(params[:id])
        saved = game.hltb_cache
        return force_search(game, saved) if saved && force?
        return render_hltb(saved, source: "cache", saved: true) if saved

        key = unsaved_key(game)
        cached = Rails.cache.read(key)
        result = cached ? cached[:result] && Hltb::Client::Result.new(**cached[:result]) : Hltb::Client.new.search(Gamedb::TitleArticle.to_front(game.title))
        unless result
          Rails.cache.write(key, { result: nil }, expires_in: UNSAVED_TTL) unless cached
          return render_no_match(game)
        end

        source = cached ? "cache" : "hltb"
        cache = build_cache(game, result)
        return save_and_render(game, cache, source:) if saveable?(game)

        Rails.cache.write(key, { result: result.to_h }, expires_in: UNSAVED_TTL) unless cached
        render_hltb(cache, source:, saved: false)
      rescue Hltb::Client::ConfigurationError => error
        render json: { error: "hltb_not_configured", message: error.message }, status: :service_unavailable
      rescue Hltb::Client::RequestError => error
        render json: { error: "hltb_lookup_failed", message: error.message }, status: :bad_gateway
      end

      private

      def force?
        ActiveModel::Type::Boolean.new.cast(params[:force]) == true
      end

      # Claims the search before scraping (so two forced lookups cannot both
      # pass the interval), and gives the claim back if the scrape fails. A
      # no-match still counts: the saved times stay.
      def force_search(game, saved)
        previous = saved.searched_at
        return render_too_soon(saved.reload) unless claim_search(saved)

        result = Hltb::Client.new.search(Gamedb::TitleArticle.to_front(game.title))
        return render_no_match(game) unless result

        saved.update!(cache_attributes(game, result))
        render_hltb(saved, source: "hltb", saved: true)
      rescue Hltb::Client::ConfigurationError, Hltb::Client::RequestError
        RpgClubHltbCache.where(cache_id: saved.cache_id).update_all(searched_at: previous)
        raise
      end

      def claim_search(saved)
        now = Time.current
        scope = RpgClubHltbCache.where(cache_id: saved.cache_id)
        unless admin_or_above?
          scope = scope.where("searched_at IS NULL OR searched_at <= ?", now - RpgClubHltbCache::FORCE_INTERVAL)
        end
        return false if scope.update_all(searched_at: now).zero?

        saved.searched_at = now
        true
      end

      def render_too_soon(saved)
        next_at = saved.next_forced_search_at&.iso8601
        render json: { error: "hltb_search_too_soon", next_forced_search_at: next_at,
                       message: "This game was searched on HowLongToBeat recently; search again after #{next_at}." },
          status: :too_many_requests
      end

      def render_no_match(game)
        render json: { error: "hltb_no_match", message: "HowLongToBeat has no match for #{game.title}." },
          status: :not_found
      end

      # A concurrent lookup may have saved the game's times first
      # (uq_hltb_game_id); those stored times are the answer.
      def save_and_render(game, cache, source:)
        cache.searched_at = Time.current
        cache.save!
        render_hltb(cache, source:, saved: true)
      rescue ActiveRecord::RecordNotUnique
        render_hltb(RpgClubHltbCache.find_by!(gamedb_game_id: game.game_id), source: "cache", saved: true)
      end

      def unsaved_key(game)
        "hltb_unsaved/v1/#{game.game_id}/#{game.title}"
      end

      def saveable?(game)
        game.initial_release_date.present? && game.initial_release_date <= SAVE_AFTER.ago
      end

      def build_cache(game, result)
        RpgClubHltbCache.new(gamedb_game_id: game.game_id, **cache_attributes(game, result))
      end

      # The scraped values as cache columns, trimmed to the column limits.
      def cache_attributes(game, result)
        attributes = result.to_h.except(:name, :url, :image_url).merge(
          hltb_name: result.name, hltb_url: result.url, hltb_image_url: result.image_url,
          source_query: game.title, scraped_at: Time.current
        )
        attributes.to_h do |column, value|
          limit = RpgClubHltbCache.columns_hash.fetch(column.to_s).limit
          [ column, value && limit ? value.to_s.first(limit) : value ]
        end
      end

      def render_hltb(cache, source:, saved:)
        render json: { data: HltbResource.new(cache).serializable_hash, meta: { source:, saved: } }
      end
    end
  end
end
