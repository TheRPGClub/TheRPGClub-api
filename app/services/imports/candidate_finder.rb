# frozen_string_literal: true

module Imports
  # GameDB candidate search for import rows, ported from the bot. Both entry
  # points query GamedbGame.search directly and return Imports::Candidate
  # arrays.
  #
  # - #find(title): the Steam / collection-CSV matcher (the bot's
  #   buildImportCandidates). Tries TitleNormalizer.progressive_variants in
  #   order; the first variant with any hits wins. Hits are scored against
  #   that variant (see #score), sorted by score then title, kept when the
  #   score is above 0 or they are in the top 3, and capped at MAX_CANDIDATES.
  # - #find_with_fallback(title): the Completionator matcher (the bot's
  #   searchGameDbWithFallback). Progressive variants, then colon/"The"
  #   permutations, then a union of single-token searches. Unscored and
  #   uncapped beyond SEARCH_LIMIT per query.
  #
  # Class helpers for the import workflows:
  # - .confidence(title, candidates) -> "exact" | "fuzzy" | nil, the value
  #   for an item's match_confidence (buildImportMatchConfidence).
  # - .dump(candidates) / .load(json): match_candidate_json in the bot's
  #   `[{"gameId":1,"title":"..."}]` shape, so items stay readable by the bot.
  #
  # Unlike the bot's GameSearchService, the search does not fold accents or
  # page to exhaustion: each variant query reads at most SEARCH_LIMIT rows in
  # GamedbGame.search order (exact, then prefix, then rating).
  class CandidateFinder
    MAX_CANDIDATES = 5
    KEEP_TOP = 3
    SEARCH_LIMIT = 100

    def self.confidence(search_title, candidates)
      return if candidates.empty?

      candidates.first.title.downcase == search_title.to_s.downcase ? "exact" : "fuzzy"
    end

    def self.dump(candidates)
      candidates.map { |candidate| { gameId: candidate.game_id, title: candidate.title } }.to_json
    end

    def self.load(json)
      return [] if json.blank?

      parsed = JSON.parse(json)
      return [] unless parsed.is_a?(Array)

      candidates = parsed.filter_map do |entry|
        next unless entry.is_a?(Hash)

        game_id = entry["gameId"].to_i
        title = entry["title"].to_s
        Candidate.new(game_id: game_id, title: title) if game_id.positive? && title.present?
      end
      candidates.uniq(&:game_id).first(MAX_CANDIDATES)
    rescue JSON::ParserError
      []
    end

    def find(title)
      TitleNormalizer.progressive_variants(sanitize(title)).each do |variant|
        hits = search(variant)
        next if hits.empty?

        return rank(variant, hits)
      end
      []
    end

    def find_with_fallback(title)
      raw = title.to_s.strip
      return [] if raw.empty?

      (TitleNormalizer.progressive_variants(raw) + permutations(raw)).each do |variant|
        hits = search(variant)
        return to_candidates(hits) if hits.any?
      end

      token_union(raw)
    end

    private

    # Lowercase ASCII alphanumerics (the bot's normalizeCandidate).
    def comparable(value)
      value.downcase.gsub(/[^a-z0-9]+/, " ").squeeze(" ").strip
    end

    def score(search, candidate)
      return 100 if candidate == search
      return 85 if candidate.start_with?(search)
      return 70 if candidate.include?(search)

      words = search.split
      return 0 if words.empty?

      ((words.count { |word| candidate.include?(word) }.to_f / words.size) * 60).floor
    end

    def rank(variant, hits)
      search = comparable(variant)
      hits
        .map { |game_id, game_title| Candidate.new(game_id:, title: game_title, score: score(search, comparable(game_title))) }
        .sort_by { |candidate| [ -candidate.score, candidate.title.downcase, candidate.title ] }
        .select.with_index { |candidate, index| candidate.score.positive? || index < KEEP_TOP }
        .uniq(&:game_id)
        .first(MAX_CANDIDATES)
    end

    # Colon / leading-"The" permutations (the bot's buildTitleVariants).
    def permutations(raw)
      variants = []
      normalized = TitleNormalizer.normalize(raw)
      variants << normalized if normalized.present? && normalized != raw

      prefix, separator, suffix = raw.partition(":")
      if separator.present?
        prefix = prefix.strip
        suffix = suffix.strip
        variants << (suffix.match?(/\Athe\s/i) ? "#{prefix}: #{suffix.sub(/\Athe\s+/i, '')}" : "#{prefix}: The #{suffix}")
        variants << "#{prefix} #{suffix}"
      else
        variants << (raw.match?(/\Athe\s/i) ? raw.sub(/\Athe\s+/i, "") : "The #{raw}")
      end

      variants.reject { |variant| variant.blank? || variant == raw }.uniq
    end

    def token_union(raw)
      tokens = raw.split.map { |token| token.gsub(/[^\p{L}\p{N}'-]/, "") }.select { |token| token.length > 1 }.uniq
      hits = tokens.flat_map { |token| search(token) }
      to_candidates(hits.uniq(&:first))
    end

    def to_candidates(hits)
      hits.map { |game_id, game_title| Candidate.new(game_id:, title: game_title) }
    end

    # [[game_id, title], ...] in GamedbGame.search order.
    def search(query)
      GamedbGame.search(query).limit(SEARCH_LIMIT).pluck(:game_id, :title)
    end

    # The parts of the bot's sanitizeUserInput that matter for a search
    # string: NFKC, and no control or zero-width characters. ™ ® © go first,
    # since NFKC would turn ™ into the letters "TM" ("Game™" -> "GameTM").
    def sanitize(title)
      title.to_s.gsub(TitleNormalizer::MARKS, "").unicode_normalize(:nfkc).gsub(/[\p{Cc}​-‏‪-‮⁠-⁯﻿]/, " ")
    end
  end
end
