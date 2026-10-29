# frozen_string_literal: true

module Imports
  # IGDB suggestions for an import row (the bot's
  # searchIgdbWithProgressiveTitleVariants): tries
  # TitleNormalizer.progressive_variants of the title in order and returns
  # the first non-empty Igdb::Client#search result, each hit tagged with
  # `already_imported` (a GameDB game with that igdb_id exists).
  #
  #   Imports::IgdbCandidateSearch.new.search("The Witcher 3: Wild Hunt (2015)")
  #   # => [{igdb_id:, name:, slug:, summary:, url:, total_rating:,
  #   #      first_release_date:, cover_url:, already_imported:}, ...]
  #
  # Raises Igdb::Client::ConfigurationError / RequestError like the client;
  # callers map them (igdb_not_configured 422, igdb_request_failed 502).
  # No authorization: item endpoints check the owner first.
  class IgdbCandidateSearch
    DEFAULT_LIMIT = 10

    def initialize(client: nil)
      @client = client
    end

    def search(title, limit: DEFAULT_LIMIT)
      TitleNormalizer.progressive_variants(title).each do |variant|
        hits = client.search(variant, limit: limit)
        return tag_imported(hits) if hits.any?
      end
      []
    end

    private

    def tag_imported(hits)
      imported = GamedbGame.where(igdb_id: hits.map { |hit| hit[:igdb_id] }).pluck(:igdb_id).to_set
      hits.map { |hit| hit.merge(already_imported: imported.include?(hit[:igdb_id])) }
    end

    def client
      @client ||= Igdb::Client.new
    end
  end
end
