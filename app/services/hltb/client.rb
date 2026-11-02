# frozen_string_literal: true

require "faraday"
require "json"
require "nokogiri"

module Hltb
  # Port of the Discord bot's HowLongToBeat scraper (b/scripts/SearchHltb.ts).
  # Google Custom Search finds the game's HLTB page ("How long is <title>?",
  # first result), then the page is fetched and read with the bot's selectors:
  # the profile header for the name, the element after each stat's <h4> label
  # for the times, and the first <img> for the image.
  #
  # Unlike the bot, which shows "no results" for any failure, a Google or HLTB
  # failure raises RequestError so callers can tell "no match" from "lookup
  # failed". A first result that is not an howlongtobeat.com page is treated as
  # no match and never fetched.
  class Client
    class ConfigurationError < StandardError; end
    class RequestError < StandardError; end

    GOOGLE_SEARCH_URL = "https://www.googleapis.com/customsearch/v1"
    HLTB_ORIGIN = "https://howlongtobeat.com"
    HLTB_HOST = /\A(?:www\.)?howlongtobeat\.com\z/i
    NAME_SELECTOR = ".GameHeader_profile_header__q_PID"
    TIMEOUT_SECONDS = 15
    # HLTB rejects obvious bots; the bot sends a random browser user agent.
    USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 " \
                 "(KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36"

    # Result field => the HLTB stat label whose next element holds the time.
    STAT_LABELS = {
      main: "Main Story",
      main_sides: "Main + Sides",
      completionist: "Completionist",
      single_player: "Single-Player",
      co_op: "Co-Op",
      vs: "Vs."
    }.freeze

    # Blank fields are nil (the bot keeps them as empty strings).
    Result = Data.define(:name, :url, :image_url, *STAT_LABELS.keys)

    # `google_http` and `page_http` are Faraday seams for specs. Credentials
    # default to GOOGLE_CUSTOM_SEARCH_API_KEY and GOOGLE_CUSTOM_SEARCH_ENGINE_ID
    # (the bot's GOOGLE_API_KEY and SEARCH_ID are accepted as fallbacks).
    def initialize(api_key: nil, search_engine_id: nil, google_http: nil, page_http: nil)
      @api_key = api_key || ENV["GOOGLE_CUSTOM_SEARCH_API_KEY"].presence || ENV["GOOGLE_API_KEY"]
      @search_engine_id = search_engine_id || ENV["GOOGLE_CUSTOM_SEARCH_ENGINE_ID"].presence || ENV["SEARCH_ID"]
      @google_http = google_http
      @page_http = page_http
    end

    # The HLTB times for `title`, or nil when no HLTB page matches.
    def search(title)
      url = first_result_link("How long is #{title}?")
      return unless hltb_page?(url)

      parse(fetch_page(url), url)
    end

    private

    def first_result_link(query)
      key, engine = credentials!
      response = get(google_http, "", { key: key, cx: engine, q: query }, "Google Custom Search")
      Array(JSON.parse(response.body)["items"]).first&.dig("link")
    rescue JSON::ParserError => error
      raise RequestError, "Google Custom Search returned invalid JSON: #{error.message}"
    end

    def fetch_page(url)
      get(page_http, url, {}, "HowLongToBeat").body.to_s
    end

    def get(connection, url, params, label)
      response = connection.get(url, params)
      raise RequestError, "#{label} returned HTTP #{response.status}." unless response.success?

      response
    rescue Faraday::Error => error
      raise RequestError, "#{label} request failed: #{error.message}"
    end

    def parse(html, url)
      doc = Nokogiri::HTML(html)
      times = STAT_LABELS.transform_values do |label|
        clean(doc.at_xpath("//h4[contains(., '#{label}')]/following-sibling::*[1]")&.text)
      end

      Result.new(
        name: clean(doc.at_css(NAME_SELECTOR)&.text),
        url: url,
        image_url: clean(doc.at_css("img")&.[]("src")),
        **times
      )
    end

    def hltb_page?(url)
      uri = URI.parse(url.to_s)
      uri.is_a?(URI::HTTPS) && uri.host.to_s.match?(HLTB_HOST)
    rescue URI::InvalidURIError
      false
    end

    def clean(text)
      text.to_s.strip.presence
    end

    def credentials!
      key = @api_key.to_s.strip
      engine = @search_engine_id.to_s.strip
      return [ key, engine ] if key.present? && engine.present?

      raise ConfigurationError, "GOOGLE_CUSTOM_SEARCH_API_KEY and GOOGLE_CUSTOM_SEARCH_ENGINE_ID must be set"
    end

    def google_http
      @google_http ||= Faraday.new(url: GOOGLE_SEARCH_URL) { |connection| connection.options.timeout = TIMEOUT_SECONDS }
    end

    def page_http
      @page_http ||= Faraday.new(
        headers: { "User-Agent" => USER_AGENT, "Origin" => HLTB_ORIGIN, "Referer" => HLTB_ORIGIN }
      ) { |connection| connection.options.timeout = TIMEOUT_SECONDS }
    end
  end
end
