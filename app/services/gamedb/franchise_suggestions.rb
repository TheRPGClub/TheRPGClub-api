# frozen_string_literal: true

module Gamedb
  # Up to three Franchises a game probably belongs to (spec api#487, ticket
  # api#489), for Game Edit's role lanes. A Franchise is suggested when:
  #
  # - `series_name`: the game's IGDB Series (GLOSSARY.md "Series") has the
  #   Franchise's name;
  # - `series_links`: other games in the game's Series are linked to it;
  # - `title_match`: the game's title contains the Franchise's name as whole
  #   words.
  #
  # Franchises the game is linked to, was unlinked from by hand, or that
  # were merged are left out. Stronger reasons come first (in the order
  # above), then Franchises with more reasons, more linked Series games, and
  # longer names.
  #
  # Each suggestion carries its likely `role` there: `add_on` when the game
  # has a parent game linked to that Franchise (with `parent_game_id`),
  # else `mainline` when most of its linked Series games are Mainline there,
  # or, with none, when its title starts with the Franchise's name; else
  # `other` (a Spin-off).
  class FranchiseSuggestions
    LIMIT = 3
    REASONS = %w[series_name series_links title_match].freeze

    Suggestion = Struct.new(:franchise, :reasons, :series_links, :series_mainline, keyword_init: true) do
      def reason = reasons.min_by { |reason| REASONS.index(reason) }
    end

    def self.for(game) = new(game).suggestions

    def initialize(game)
      @game = game
    end

    # `[{ franchise:, reason:, reasons:, role:, parent_game_id:,
    # parent_title:, series_games_linked: }]`, best first.
    def suggestions
      candidates = {}
      add_series_name(candidates)
      add_series_links(candidates)
      add_title_matches(candidates)

      candidates.except(*excluded_ids).values.sort_by { |candidate| rank(candidate) }.first(LIMIT)
        .map { |candidate| as_json(candidate) }
    end

    private

    attr_reader :game

    def candidate(candidates, franchise)
      candidates[franchise.franchise_id] ||=
        Suggestion.new(franchise: franchise, reasons: [], series_links: 0, series_mainline: 0)
    end

    def add_series_name(candidates)
      series_name = game.collection_id && GamedbCollection.where(collection_id: game.collection_id).pick(:name)
      return if series_name.blank?

      GamedbFranchise.current.where("lower(btrim(name)) = lower(btrim(?))", series_name).find_each do |franchise|
        candidate(candidates, franchise).reasons << "series_name"
      end
    end

    def add_series_links(candidates)
      return unless game.collection_id

      counts = GamedbGameFranchise.joins(:game)
        .where(gamedb_games: { collection_id: game.collection_id })
        .where.not(game_id: game.game_id)
        .group(:franchise_id)
        .pluck(:franchise_id, Arel.sql("count(*)"), Arel.sql("count(*) filter (where mainline)"))
      franchises = GamedbFranchise.current.where(franchise_id: counts.map(&:first)).index_by(&:franchise_id)

      counts.each do |franchise_id, linked, mainline|
        next unless (franchise = franchises[franchise_id])

        suggestion = candidate(candidates, franchise)
        suggestion.reasons << "series_links"
        suggestion.series_links = linked
        suggestion.series_mainline = mainline
      end
    end

    # Narrowed in SQL to names inside the title, then kept only where the
    # name stands as whole words ("Ys" is in "Ys VIII", not in "Odyssey").
    def add_title_matches(candidates)
      title = game.title.to_s
      GamedbFranchise.current.where("strpos(lower(?), lower(btrim(name))) > 0", title).find_each do |franchise|
        candidate(candidates, franchise).reasons << "title_match" if whole_words?(title, franchise.name.strip)
      end
    end

    def whole_words?(title, name)
      title.match?(/(?<![[:alnum:]])#{Regexp.escape(name)}(?![[:alnum:]])/i)
    end

    def excluded_ids
      GamedbGameFranchise.where(game_id: game.game_id).pluck(:franchise_id) +
        GamedbFranchiseUnlink.where(game_id: game.game_id).pluck(:franchise_id)
    end

    def rank(candidate)
      name = candidate.franchise.name.to_s
      [ REASONS.index(candidate.reason), -candidate.reasons.size, -candidate.series_links, -name.length,
        name.downcase, candidate.franchise.franchise_id ]
    end

    def as_json(candidate)
      add_on = parent_franchise_ids.include?(candidate.franchise.franchise_id)
      { franchise: FranchiseResource.new(candidate.franchise).serializable_hash,
        reason: candidate.reason,
        reasons: REASONS & candidate.reasons,
        role: add_on ? "add_on" : main_role(candidate),
        parent_game_id: add_on ? parent&.game_id : nil,
        parent_title: add_on ? parent&.title : nil,
        series_games_linked: candidate.series_links }
    end

    def main_role(candidate)
      mainline =
        if candidate.series_links.positive?
          candidate.series_mainline * 2 > candidate.series_links
        else
          game.title.to_s.match?(/\A#{Regexp.escape(candidate.franchise.name.strip)}(?![[:alnum:]])/i)
        end
      mainline ? "mainline" : "other"
    end

    # The game's parent (GLOSSARY.md "Add-on") when it is in GameDB.
    def parent
      return @parent if defined?(@parent)

      @parent = game.parent_igdb_id && GamedbGame.select(:game_id, :title).find_by(igdb_id: game.parent_igdb_id)
    end

    def parent_franchise_ids
      @parent_franchise_ids ||= parent ? GamedbGameFranchise.where(game_id: parent.game_id).pluck(:franchise_id) : []
    end
  end
end
