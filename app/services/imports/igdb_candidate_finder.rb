# frozen_string_literal: true

module Imports
  # IGDB suggestions for an import row (the bot's
  # searchIgdbWithProgressiveTitleVariants), for the owner-scoped
  # `igdb_candidates` item endpoints:
  #
  #   Imports::IgdbCandidateFinder.new.find("Hades™ (2020)")
  #   # => [{ igdb_id:, name:, slug:, summary:, url:, total_rating:,
  #   #       first_release_date:, cover_url:, already_imported: }, ...]
  #
  # Tries TitleNormalizer.progressive_variants in order and returns the first
  # variant's non-empty Igdb::Client#search results (at most `limit`), each
  # tagged with `already_imported` (a GameDB game has that igdb_id).
  # Igdb::Client::ConfigurationError / RequestError propagate to the caller.
  class IgdbCandidateFinder
    DEFAULT_LIMIT = 10

    def initialize(client: nil)
      @client = client
    end

    def find(title, limit: DEFAULT_LIMIT)
      TitleNormalizer.progressive_variants(title).each do |variant|
        results = client.search(variant, limit: limit)
        return tag_imported(results) if results.any?
      end
      []
    end

    private

    def tag_imported(results)
      imported = GamedbGame.where(igdb_id: results.map { |result| result[:igdb_id] }).pluck(:igdb_id).to_set
      results.map { |result| result.merge(already_imported: imported.include?(result[:igdb_id])) }
    end

    def client
      @client ||= Igdb::Client.new
    end
  end
end
