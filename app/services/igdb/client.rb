# frozen_string_literal: true

require "faraday"
require "json"

module Igdb
  class Client
    class ConfigurationError < StandardError; end
    class RequestError < StandardError; end

    TOKEN_URL = "https://id.twitch.tv/oauth2/token"
    API_BASE_URL = "https://api.igdb.com/v4"
    IMAGE_BASE_URL = "https://images.igdb.com/igdb/image/upload"

    # Upper bound on the candidates a single search proxy call may return.
    SEARCH_LIMIT = 50

    # Lightweight candidate field list shared by the search paths (#search,
    # #multi_search, #search_by_ids) — enough for a caller to pick an igdb_id to
    # import, without the taxonomy/release detail that #game pulls.
    SEARCH_FIELDS = "id,name,slug,summary,url,total_rating,first_release_date,cover.image_id"

    def self.image_url(image_id, size:, extension: "jpg")
      "#{IMAGE_BASE_URL}/t_#{size}/#{image_id}.#{extension}"
    end

    # Proxy an IGDB `games` title search. Returns lightweight candidate hashes
    # (id, name, dates, cover url) so a caller can pick the right `igdb_id` to
    # import. The DB-derived `already_imported` flag is layered on by the
    # controller — this method never touches the database.
    def search(query, limit: 25)
      term = query.to_s.strip
      return [] if term.blank?

      capped = limit.to_i.clamp(1, SEARCH_LIMIT)
      payload = post_igdb(
        "games",
        <<~QUERY.squish
          fields #{SEARCH_FIELDS};
          search "#{escape_search(term)}";
          limit #{capped};
        QUERY
      )

      Array(payload).map { |game| search_result(game) }
    end

    # Search several titles in one IGDB multiquery — a single HTTP round-trip
    # (so it costs the shared credential one request, not one per title).
    # Returns the same candidate hashes as #search, deduped by igdb_id across
    # terms (the first term that matched a game keeps it) and each tagged with
    # the `matched_query` it came from, so a bulk importer can resolve many
    # titles at once. Blank terms are dropped; [] for none. The caller must keep
    # the term count within IGDB's 10-query multiquery cap.
    def multi_search(queries, limit: 25)
      terms = Array(queries).map { |query| query.to_s.strip }.reject(&:blank?)
      return [] if terms.empty?

      capped = limit.to_i.clamp(1, SEARCH_LIMIT)
      body = terms.each_with_index.map do |term, index|
        <<~QUERY.squish
          query games "q#{index}" {
            fields #{SEARCH_FIELDS};
            search "#{escape_search(term)}";
            limit #{capped};
          };
        QUERY
      end.join("\n")

      collect_multi_results(post_igdb("multiquery", body), terms)
    end

    # Look specific IGDB games up by `id`, returning the same lightweight
    # candidate hashes as #search. Lets a caller resolve igdb_ids it already has
    # (the bot) instead of a fuzzy title match (the web). Ids are deduped;
    # unknown ids are simply absent from the result. Returns [] for no ids. Like
    # #search this never touches the database — the controller layers on
    # `already_imported`.
    def search_by_ids(ids, limit: 25)
      wanted = Array(ids).map { |id| Integer(id) }.uniq
      return [] if wanted.empty?

      capped = limit.to_i.clamp(1, SEARCH_LIMIT)
      payload = post_igdb(
        "games",
        <<~QUERY.squish
          fields #{SEARCH_FIELDS};
          where id = (#{wanted.join(',')});
          limit #{capped};
        QUERY
      )

      Array(payload).map { |game| search_result(game) }
    end

    # Fetch the full game payload for one `igdb_id`, normalized into the shape
    # Gamedb::IgdbGameImporter consumes (metadata + taxonomy refs + release
    # dates + cover/artworks). Field list mirrors the Discord bot's IGDB scan so
    # an API-created game matches a bot-created one. Returns nil when not found.
    def game(igdb_id)
      payload = post_igdb(
        "games",
        <<~QUERY.squish
          fields id,name,slug,summary,url,total_rating,first_release_date,
            parent_game.id,parent_game.name,
            collection.id,collection.name,
            cover.image_id,
            artworks.image_id,artworks.alpha_channel,artworks.artwork_type.slug,
            genres.id,genres.name,
            platforms.id,platforms.name,
            themes.id,themes.name,
            game_modes.id,game_modes.name,
            player_perspectives.id,player_perspectives.name,
            game_engines.id,game_engines.name,
            franchises.id,franchises.name,
            involved_companies.company.id,involved_companies.company.name,
            involved_companies.developer,involved_companies.publisher,
            release_dates.region,release_dates.date,release_dates.y,release_dates.m,
            release_dates.platform.id,release_dates.platform.name;
          where id = #{Integer(igdb_id)};
          limit 1;
        QUERY
      )
      game = payload.first
      return if game.blank?

      game_hash(game)
    end

    def game_images(igdb_id)
      payload = post_igdb(
        "games",
        <<~QUERY.squish
          fields id,name,cover.image_id,artworks.image_id,artworks.alpha_channel,artworks.artwork_type.slug;
          where id = #{Integer(igdb_id)};
          limit 1;
        QUERY
      )
      game = payload.first
      return if game.blank?

      {
        igdb_id: game["id"],
        title: game["name"],
        cover_image_id: game.dig("cover", "image_id"),
        artworks: Array(game["artworks"]).filter_map { |artwork| artwork_hash(artwork) }
      }
    end

    private

    # Flatten an IGDB multiquery payload (an array of `{ "name", "result" }`)
    # back into one candidate list in the original term order, tagging each with
    # the term that found it and dropping any igdb_id an earlier term already
    # claimed (so an overlapping title doesn't surface the same game twice).
    def collect_multi_results(payload, terms)
      by_name = Array(payload).index_by { |entry| entry["name"] }
      seen = Set.new

      terms.each_with_index.flat_map do |term, index|
        Array(by_name["q#{index}"]&.fetch("result", nil)).filter_map do |game|
          candidate = search_result(game)
          next if seen.include?(candidate[:igdb_id])

          seen << candidate[:igdb_id]
          candidate.merge(matched_query: term)
        end
      end
    end

    def search_result(game)
      cover_image_id = game.dig("cover", "image_id").presence
      {
        igdb_id: game["id"],
        name: game["name"],
        slug: game["slug"].presence,
        summary: game["summary"].presence,
        url: game["url"].presence,
        total_rating: game["total_rating"],
        first_release_date: unix_to_time(game["first_release_date"])&.iso8601,
        cover_url: cover_image_id && self.class.image_url(cover_image_id, size: "cover_big")
      }
    end

    def game_hash(game)
      {
        igdb_id: game["id"],
        name: game["name"],
        slug: game["slug"].presence,
        summary: game["summary"].presence,
        url: game["url"].presence,
        total_rating: game["total_rating"],
        first_release_date: unix_to_time(game["first_release_date"]),
        parent_igdb_id: game.dig("parent_game", "id"),
        parent_game_name: game.dig("parent_game", "name").presence,
        collection: named_ref(game["collection"]),
        cover_image_id: game.dig("cover", "image_id").presence,
        artworks: Array(game["artworks"]).filter_map { |artwork| artwork_hash(artwork) },
        genres: named_refs(game["genres"]),
        platforms: named_refs(game["platforms"]),
        themes: named_refs(game["themes"]),
        game_modes: named_refs(game["game_modes"]),
        perspectives: named_refs(game["player_perspectives"]),
        engines: named_refs(game["game_engines"]),
        franchises: named_refs(game["franchises"]),
        companies: Array(game["involved_companies"]).filter_map { |company| company_hash(company) },
        release_dates: Array(game["release_dates"]).filter_map { |release| release_date_hash(release) }
      }
    end

    # An IGDB `{ id, name }` node -> `{ igdb_id:, name: }`, or nil when either is
    # missing (so a half-populated reference never becomes a nameless lookup row).
    def named_ref(node)
      return if node.blank?

      igdb_id = node["id"]
      name = node["name"].presence
      return if igdb_id.blank? || name.blank?

      { igdb_id: igdb_id, name: name }
    end

    def named_refs(nodes)
      Array(nodes).filter_map { |node| named_ref(node) }
    end

    def company_hash(involved_company)
      ref = named_ref(involved_company["company"])
      return if ref.nil?

      ref.merge(
        developer: involved_company["developer"] == true,
        publisher: involved_company["publisher"] == true
      )
    end

    def release_date_hash(release)
      platform = named_ref(release["platform"])
      return if platform.nil?

      {
        platform: platform,
        region: release["region"],
        date: unix_to_time(release["date"]) || year_month_to_time(release["y"], release["m"])
      }
    end

    def unix_to_time(value)
      return if value.blank?

      Time.at(Integer(value)).utc
    rescue ArgumentError, TypeError
      nil
    end

    def year_month_to_time(year, month)
      return if year.blank?

      Time.utc(Integer(year), month.present? ? Integer(month) : 1, 1)
    rescue ArgumentError, TypeError
      nil
    end

    # Defang the user term before it lands inside the quoted apicalypse
    # `search "..."` clause: drop the quote/backslash chars that would break out
    # of the string.
    def escape_search(term)
      term.gsub(/["\\]/, " ")
    end

    def artwork_hash(artwork)
      image_id = artwork["image_id"].presence
      return if image_id.blank?

      {
        image_id: image_id,
        alpha_channel: artwork["alpha_channel"] == true,
        artwork_type_slug: artwork.dig("artwork_type", "slug").to_s
      }
    end

    def post_igdb(path, body)
      response = Faraday.post("#{API_BASE_URL}/#{path}") do |request|
        request.headers["Client-ID"] = client_id
        request.headers["Authorization"] = "Bearer #{access_token}"
        request.headers["Content-Type"] = "text/plain"
        request.body = body
        request.options.timeout = 20
      end

      parse_json_response!(response, "IGDB #{path} request")
    rescue Faraday::Error => error
      raise RequestError, "IGDB #{path} request failed: #{error.message}"
    end

    def access_token
      return @access_token if @access_token.present? && Time.current < @access_token_expires_at

      response = Faraday.post(TOKEN_URL) do |request|
        request.headers["Content-Type"] = "application/x-www-form-urlencoded"
        request.body = {
          client_id: client_id,
          client_secret: client_secret,
          grant_type: "client_credentials"
        }.to_query
        request.options.timeout = 20
      end

      payload = parse_json_response!(response, "IGDB token request")
      @access_token = payload.fetch("access_token")
      @access_token_expires_at = Time.current + payload.fetch("expires_in").to_i - 60
      @access_token
    rescue Faraday::Error => error
      raise RequestError, "IGDB token request failed: #{error.message}"
    end

    def client_id
      value = ENV.fetch("IGDB_CLIENT_ID", ENV.fetch("TWITCH_CLIENT_ID", nil)).to_s.strip
      return value if value.present? && value != "change_me"

      raise ConfigurationError, "IGDB_CLIENT_ID must be set"
    end

    def client_secret
      value = ENV.fetch("IGDB_CLIENT_SECRET", ENV.fetch("TWITCH_CLIENT_SECRET", nil)).to_s.strip
      return value if value.present? && value != "change_me"

      raise ConfigurationError, "IGDB_CLIENT_SECRET must be set"
    end

    def parse_json_response!(response, label)
      payload = JSON.parse(response.body)
      return payload if response.success?

      raise RequestError, "#{label} failed with HTTP #{response.status}: #{error_message(payload)}"
    rescue JSON::ParserError
      raise RequestError, "#{label} failed with HTTP #{response.status}"
    end

    def error_message(payload)
      return payload.to_json unless payload.is_a?(Hash)

      payload["message"] || payload["error_description"] || payload["error"] || payload.to_json
    end
  end
end
