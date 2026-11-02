# frozen_string_literal: true

require "base64"
require "faraday"
require "json"
require "openssl"

module Github
  # GitHub App client, ported from the Discord bot's GithubIssuesService
  # (b/src/services/GithubIssuesService.ts): signs an RS256 app JWT, trades it
  # for an installation token (kept in process until a minute before it
  # expires), then calls the REST API as the installation. Only what
  # Suggestion review needs is ported: create an issue and read its state.
  #
  # Credentials default to GITHUB_APP_ID, GITHUB_APP_INSTALLATION_ID and
  # GITHUB_APP_PRIVATE_KEY (the bot's names). The private key may be a PEM
  # with real newlines, literal "\n" escapes, or its body on one line.
  class Client
    class ConfigurationError < StandardError; end
    class RequestError < StandardError; end

    API_BASE = "https://api.github.com"
    API_VERSION = "2022-11-28"
    TIMEOUT_SECONDS = 15
    # Refresh the installation token when it has less than this left.
    TOKEN_MARGIN = 60

    Issue = Data.define(:number, :url, :state)

    @token_cache = {}
    @token_mutex = Mutex.new

    class << self
      attr_reader :token_mutex

      def cached_token(installation_id, now)
        token_mutex.synchronize do
          entry = @token_cache[installation_id]
          entry[:token] if entry && entry[:expires_at] - now > TOKEN_MARGIN
        end
      end

      def store_token(installation_id, token, expires_at)
        token_mutex.synchronize { @token_cache[installation_id] = { token:, expires_at: } }
      end

      # For specs.
      def reset_token_cache!
        token_mutex.synchronize { @token_cache = {} }
      end
    end

    # `timeout` is the per-request timeout in seconds. `http` (a Faraday
    # connection) and `clock` (returns a Time) are seams for specs.
    def initialize(app_id: nil, installation_id: nil, private_key: nil, timeout: TIMEOUT_SECONDS, http: nil, clock: nil)
      @app_id = (app_id.nil? ? ENV["GITHUB_APP_ID"] : app_id).to_s.strip
      @installation_id = (installation_id.nil? ? ENV["GITHUB_APP_INSTALLATION_ID"] : installation_id).to_s.strip
      @private_key = (private_key.nil? ? ENV["GITHUB_APP_PRIVATE_KEY"] : private_key).to_s
      @timeout = timeout
      @http = http
      @clock = clock || -> { Time.current }
    end

    def configured?
      missing_settings.empty?
    end

    # Opens an issue in `repo` ("owner/name") and returns its Issue.
    def create_issue(repo:, title:, body:, labels: [])
      raw = request(:post, "/repos/#{repo}/issues", { title:, body:, labels: })
      to_issue(raw)
    end

    # "open" or "closed", or nil when the issue does not exist (or is a pull request).
    def issue_state(repo:, number:)
      raw = request(:get, "/repos/#{repo}/issues/#{Integer(number)}")
      return if raw["pull_request"]

      raw["state"] == "closed" ? "closed" : "open"
    rescue NotFound
      nil
    end

    private

    class NotFound < RequestError; end
    private_constant :NotFound

    def request(method, path, body = nil, token: installation_token)
      send_request(method, path, body, "token #{token}")
    end

    def send_request(method, path, body, authorization)
      response = http.run_request(method, path, body&.to_json, headers(authorization))
      parsed = parse(response.body)
      return parsed if response.success?

      message = "GitHub returned HTTP #{response.status} for #{method.upcase} #{path}: #{parsed['message'] || 'no message'}"
      raise NotFound, message if response.status == 404

      raise RequestError, message
    rescue Faraday::Error => error
      raise RequestError, "GitHub request failed: #{error.message}"
    end

    def installation_token
      now = @clock.call
      cached = self.class.cached_token(@installation_id, now)
      return cached if cached

      raise ConfigurationError, "Missing GitHub App config: #{missing_settings.join(', ')}" unless configured?

      raw = send_request(:post, "/app/installations/#{@installation_id}/access_tokens", {}, "Bearer #{app_jwt(now)}")
      token = raw["token"].presence
      expires_at = raw["expires_at"].presence
      raise RequestError, "GitHub did not return an installation token." unless token && expires_at

      self.class.store_token(@installation_id, token, Time.zone.parse(expires_at))
      token
    end

    def app_jwt(now)
      header = base64url({ alg: "RS256", typ: "JWT" }.to_json)
      payload = base64url({ iat: now.to_i - 60, exp: now.to_i + 540, iss: Integer(@app_id) }.to_json)
      data = "#{header}.#{payload}"
      signature = signing_key.sign(OpenSSL::Digest.new("SHA256"), data)
      "#{data}.#{base64url(signature)}"
    rescue ArgumentError, OpenSSL::PKey::PKeyError => error
      raise ConfigurationError, "GitHub App credentials are invalid: #{error.class}"
    end

    # The bot's normalizePrivateKey: restore escaped newlines, then rewrap the
    # body at 64 characters between its BEGIN and END lines.
    def signing_key
      key = @private_key.gsub("\\n", "\n").strip
      header = key[/-----BEGIN [^-]+-----/]
      footer = key[/-----END [^-]+-----/]
      if header && footer
        body = key.sub(header, "").sub(footer, "").gsub(/\s+/, "")
        key = [ header, *body.scan(/.{1,64}/), footer ].join("\n")
      end
      OpenSSL::PKey::RSA.new(key)
    end

    def missing_settings
      { "GITHUB_APP_ID" => @app_id, "GITHUB_APP_INSTALLATION_ID" => @installation_id,
        "GITHUB_APP_PRIVATE_KEY" => @private_key.strip }.select { |_name, value| value.empty? }.keys
    end

    def headers(authorization)
      { "Authorization" => authorization, "Accept" => "application/vnd.github+json",
        "X-GitHub-Api-Version" => API_VERSION, "Content-Type" => "application/json",
        "User-Agent" => "RPGClubApi" }
    end

    def parse(body)
      body.to_s.empty? ? {} : JSON.parse(body.to_s)
    rescue JSON::ParserError
      {}
    end

    def to_issue(raw)
      Issue.new(number: raw.fetch("number"), url: raw["html_url"].to_s, state: raw["state"] == "closed" ? "closed" : "open")
    end

    def base64url(value)
      Base64.urlsafe_encode64(value, padding: false)
    end

    def http
      @http ||= Faraday.new(url: API_BASE) { |connection| connection.options.timeout = @timeout }
    end
  end
end
