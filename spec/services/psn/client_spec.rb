# frozen_string_literal: true

require "rails_helper"

RSpec.describe Psn::Client do
  include ActiveSupport::Testing::TimeHelpers

  subject(:client) do
    described_class.new(
      npsso: "test-npsso", http: http, cache: cache, hub_state: hub_state, sleeper: ->(seconds) { sleeps << seconds }
    )
  end

  # In-memory stand-in for AchievementHubState (get/set), so the spec does not
  # depend on the hub state table.
  let(:hub_state_class) do
    Class.new do
      attr_reader :values, :writes

      def initialize
        @values = {}
        @writes = []
      end

      def get(key) = values[key]

      def set(key, value)
        writes << [ key, value ]
        values[key] = value
      end
    end
  end
  let(:hub_state) { hub_state_class.new }
  let(:cache) { ActiveSupport::Cache::MemoryStore.new }
  let(:sleeps) { [] }
  let(:account_id) { "2984038888603282554" }
  let(:redirect_with_code) { "com.scee.psxandroid.scecompcall://redirect/?code=v3.AUTHCODE&cid=abc" }

  # A tiny router over Faraday's test adapter. Every request goes through
  # `dispatch`, which logs it in `requests` and hands it to the first matching
  # route; a route replies with each queued response in turn (repeating the
  # last). An unrouted request fails the example, so nothing reaches Sony.
  let(:routes) { Hash.new { |hash, key| hash[key] = [] } }
  let(:requests) { [] }
  let(:stubs) { Faraday::Adapter::Test::Stubs.new }
  let(:http) { Faraday.new { |builder| builder.adapter(:test, stubs) } }

  let(:route_class) do
    Struct.new(:match, :replies, :calls) do
      def reply!
        self.calls += 1
        reply = replies.length > 1 ? replies.shift : replies.first
        reply.is_a?(Exception) ? raise(reply) : reply
      end
    end
  end

  def stub_http(method, url, match: ->(_request) { true }, reply: nil, replies: [ reply ])
    key = [ method, url ]
    if routes[key].empty?
      stubs.public_send(method, url) { |env| dispatch(key, env) }
    end
    route_class.new(match, replies.dup, 0).tap { |route| routes[key] << route }
  end

  def dispatch(key, env)
    request = {
      url: env.url.to_s, params: env.params, headers: env.request_headers,
      form: env.body.is_a?(String) && env.request_headers["Content-Type"]&.include?("form") ? URI.decode_www_form(env.body).to_h : nil,
      json: env.request_headers["Content-Type"]&.include?("json") ? JSON.parse(env.body) : nil
    }
    requests << request
    route = routes[key].find { |candidate| candidate.match.call(request) }
    raise "Unstubbed PSN request: #{key.inspect} #{request.inspect}" unless route

    route.reply!
  end

  def json(body = {}, status: 200, headers: {})
    [ status, { "Content-Type" => "application/json" }.merge(headers), body.to_json ]
  end

  def stub_authorize(location: redirect_with_code)
    stub_http(:get, described_class::AUTHORIZE_URL,
      match: ->(request) {
        request[:params]["client_id"] == described_class::OAUTH_CLIENT_ID &&
          request[:params]["response_type"] == "code" && request[:headers]["Cookie"] == "npsso=test-npsso"
      },
      reply: [ 302, { "Location" => location }, "" ])
  end

  def token_body(access_token, refresh_token)
    { access_token: access_token, expires_in: 3599, refresh_token: refresh_token,
      refresh_token_expires_in: 5_183_999, token_type: "bearer" }
  end

  def stub_code_exchange(access_token: "access-1", refresh_token: "refresh-1")
    stub_http(:post, described_class::TOKEN_URL,
      match: ->(request) {
        request[:form]&.values_at("grant_type", "code") == %w[authorization_code v3.AUTHCODE] &&
          request[:headers]["Authorization"] == described_class::CLIENT_AUTH
      },
      reply: json(token_body(access_token, refresh_token)))
  end

  def requests_to(url)
    requests.select { |request| request[:url].start_with?(url) }
  end

  def titles_url(id = account_id)
    "https://m.np.playstation.com/api/trophy/v1/users/#{id}/trophyTitles"
  end

  def title_row(np_comm_id, updated_at, service: "trophy2", name: "Game #{np_comm_id}")
    {
      npServiceName: service, npCommunicationId: np_comm_id, trophySetVersion: "01.00",
      trophyTitleName: name, trophyTitleIconUrl: "https://image.api.playstation.com/#{np_comm_id}.png",
      trophyTitlePlatform: service == "trophy2" ? "PS5" : "PS4,PSVITA", hasTrophyGroups: false,
      definedTrophies: { bronze: 10, silver: 3, gold: 1, platinum: 1 }, progress: 40,
      earnedTrophies: { bronze: 5, silver: 1, gold: 0, platinum: 0 }, hiddenFlag: false,
      lastUpdatedDateTime: updated_at
    }
  end

  def stub_titles(rows, offset: 0, total: rows.size, token: "access-1")
    stub_http(:get, titles_url,
      match: ->(request) {
        request[:params] == { "limit" => described_class::TITLES_PAGE.to_s, "offset" => offset.to_s } &&
          request[:headers]["Authorization"] == "Bearer #{token}"
      },
      reply: json({ trophyTitles: rows, totalItemCount: total }))
  end

  def stub_titles_reply(*replies)
    stub_http(:get, titles_url, replies: replies)
  end

  describe "auth" do
    it "exchanges the NPSSO for an access token and caches it" do
      stub_authorize
      stub_code_exchange
      titles = stub_titles([])

      client.played_sets(account_id)
      client.played_sets(account_id)

      expect(requests_to(described_class::AUTHORIZE_URL).size).to eq(1)
      expect(titles.calls).to eq(2)
    end

    it "renews an expired access token with the cached refresh token instead of the NPSSO" do
      stub_authorize
      stub_code_exchange
      stub_titles([])
      refresh = stub_http(:post, described_class::TOKEN_URL,
        match: ->(request) { request[:form]&.values_at("grant_type", "refresh_token") == %w[refresh_token refresh-1] },
        reply: json(token_body("access-2", "refresh-2")))
      second = stub_titles([], token: "access-2")

      client.played_sets(account_id)
      travel(3600.seconds) { client.played_sets(account_id) }

      expect(refresh.calls).to eq(1)
      expect(second.calls).to eq(1)
      expect(requests_to(described_class::AUTHORIZE_URL).size).to eq(1)
    end

    it "raises AuthExpired and records psn_auth_expired_at once when the NPSSO no longer yields a code" do
      stub_authorize(location: "com.scee.psxandroid.scecompcall://redirect/?error=login_required")

      freeze_time do
        2.times do
          expect { client.played_sets(account_id) }.to raise_error(Achievements::Providers::AuthExpired)
        end

        expect(hub_state.writes).to eq([ [ "psn_auth_expired_at", Time.current.iso8601 ] ])
      end
    end

    it "clears psn_auth_expired_at after a successful auth" do
      hub_state.set("psn_auth_expired_at", "2026-10-01T00:00:00Z")
      stub_authorize
      stub_code_exchange
      stub_titles([])

      client.played_sets(account_id)

      expect(hub_state.get("psn_auth_expired_at")).to be_nil
    end

    it "records the expiry in AchievementHubState by default, and clears it on the next success" do
      client = described_class.new(npsso: "test-npsso", http: http, cache: cache)
      stub_authorize(location: "com.scee.psxandroid.scecompcall://redirect/?error=login_required")

      freeze_time do
        expect { client.played_sets(account_id) }.to raise_error(Achievements::Providers::AuthExpired)
        expect(AchievementHubState.get("psn_auth_expired_at")).to eq(Time.current.iso8601)
      end

      routes.clear
      stub_authorize
      stub_code_exchange
      stub_titles([])
      client.played_sets(account_id)

      expect(AchievementHubState.get("psn_auth_expired_at")).to be_nil
    end

    it "raises AuthExpired when Sony refuses the code exchange" do
      stub_authorize
      stub_http(:post, described_class::TOKEN_URL, reply: json({ error: "invalid_grant" }, status: 400))

      expect { client.played_sets(account_id) }.to raise_error(Achievements::Providers::AuthExpired)
      expect(hub_state.get("psn_auth_expired_at")).to be_present
    end
  end

  describe "#played_sets" do
    before do
      stub_authorize
      stub_code_exchange
    end

    it "normalises the member's trophy titles into PlayedSets" do
      stub_titles([ title_row("NPWR20188_00", "2026-10-30T12:00:00Z") ])

      played = client.played_sets(account_id)

      expect(played).to contain_exactly(
        have_attributes(
          class: Achievements::Providers::PlayedSet,
          external_id: "NPWR20188_00",
          np_service_name: "trophy2",
          title: "Game NPWR20188_00",
          platform_label: "PS5",
          icon_url: "https://image.api.playstation.com/NPWR20188_00.png",
          activity_at: Time.utc(2026, 10, 30, 12),
          achievements_count: 15
        )
      )
    end

    it "pages through every title without since" do
      stub_titles([ title_row("NPWR1_00", "2026-10-30T12:00:00Z") ], total: 2)
      stub_titles([ title_row("NPWR2_00", "2020-01-01T00:00:00Z", service: "trophy") ], offset: 1, total: 2)

      expect(client.played_sets(account_id).map(&:external_id)).to eq(%w[NPWR1_00 NPWR2_00])
    end

    it "with since, stops at the first title last updated before it" do
      stub_titles([
        title_row("NPWR1_00", "2026-10-30T12:00:00Z"),
        title_row("NPWR2_00", "2026-10-29T00:00:00Z"),
        title_row("NPWR3_00", "2026-10-01T00:00:00Z")
      ], total: 1_500)

      played = client.played_sets(account_id, since: Time.utc(2026, 10, 28))

      expect(played.map(&:external_id)).to eq(%w[NPWR1_00 NPWR2_00])
      expect(requests_to(titles_url).map { |request| request[:params]["offset"] }).to eq(%w[0])
    end

    it "raises Private on Sony's access-control error, even with HTTP 200" do
      stub_titles_reply(json({ error: { referenceId: "abc", code: 2_240_526, message: "Not permitted by access control" } }))

      expect { client.played_sets(account_id) }.to raise_error(Achievements::Providers::Private)
    end

    it "raises Private on a 403 access-control error" do
      stub_titles_reply(json({ error: { code: 2_240_526, message: "Not permitted by access control" } }, status: 403))

      expect { client.played_sets(account_id) }.to raise_error(Achievements::Providers::Private)
    end

    it "raises NotFound for an unknown accountId" do
      stub_titles_reply(json({ error: { code: 2_240_525, message: "Resource not found" } }, status: 404))

      expect { client.played_sets(account_id) }.to raise_error(Achievements::Providers::NotFound)
    end

    it "raises RateLimited on 429, carrying Retry-After" do
      stub_titles_reply([ 429, { "Retry-After" => "3" }, "" ])

      expect { client.played_sets(account_id) }
        .to raise_error(Achievements::Providers::RateLimited) { |error| expect(error.retry_after).to eq(3.0) }
    end

    it "retries once after an SSL EOF" do
      stub_titles_reply(
        Faraday::SSLError.new("SSL_read: unexpected eof while reading"),
        json({ trophyTitles: [ title_row("NPWR1_00", "2026-10-30T12:00:00Z") ], totalItemCount: 1 })
      )

      expect(client.played_sets(account_id).map(&:external_id)).to eq(%w[NPWR1_00])
    end

    it "retries a transient 5xx with a short backoff" do
      stub_titles_reply([ 503, {}, "" ], json({ trophyTitles: [], totalItemCount: 0 }))

      expect(client.played_sets(account_id)).to eq([])
      expect(sleeps).to eq([ 0.5 ])
    end
  end

  describe "#resolve_account" do
    before do
      stub_authorize
      stub_code_exchange
    end

    def search_result(online_id, id)
      { socialMetadata: { accountId: id, onlineId: online_id, country: "PT",
                          avatarUrl: "https://psn-rsc.prod.dl.playstation.net/#{id}.png" } }
    end

    def stub_search(*results)
      stub_http(:post, described_class::SEARCH_URL,
        match: ->(request) {
          request[:json] == { "searchTerm" => "Xergg", "domainRequests" => [ { "domain" => "SocialAllAccounts" } ] }
        },
        reply: json({ domainResponses: [ { domain: "SocialAllAccounts", results: results } ] }))
    end

    it "resolves an online ID to its accountId by exact, case-insensitive search match" do
      stub_search(search_result("Xergg_2", "111"), search_result("xergg", account_id))

      expect(client.resolve_account("Xergg")).to eq(
        external_id: account_id,
        display_name: "xergg",
        avatar_url: "https://psn-rsc.prod.dl.playstation.net/#{account_id}.png"
      )
    end

    it "falls back to the profile endpoint when search has no exact match" do
      stub_search(search_result("Xergg_2", "111"))
      stub_http(:get, format(described_class::PROFILE_URL, "Xergg"),
        reply: json({ profile: { onlineId: "Xergg", accountId: account_id,
                                 avatarUrls: [ { size: "l", avatarUrl: "https://example.test/a.png" } ] } }))

      expect(client.resolve_account("Xergg")).to eq(
        external_id: account_id, display_name: "Xergg", avatar_url: "https://example.test/a.png"
      )
    end

    it "raises NotFound for an unknown online ID" do
      stub_search
      stub_http(:get, format(described_class::PROFILE_URL, "Xergg"),
        reply: json({ error: { code: 2_105_356, message: "User not found" } }, status: 404))

      expect { client.resolve_account("Xergg") }.to raise_error(Achievements::Providers::NotFound)
    end
  end

  describe "#set_with_progress" do
    let(:np_comm_id) { "NPWR20188_00" }
    let(:definitions_url) { "https://m.np.playstation.com/api/trophy/v1/npCommunicationIds/#{np_comm_id}/trophyGroups/all/trophies" }
    let(:earned_url) do
      "https://m.np.playstation.com/api/trophy/v1/users/#{account_id}/npCommunicationIds/#{np_comm_id}/trophyGroups/all/trophies"
    end

    before do
      stub_authorize
      stub_code_exchange
      stub_http(:get, definitions_url, match: ->(request) { request[:params] == { "npServiceName" => "trophy2" } },
        reply: json({
          trophySetVersion: "01.10", hasTrophyGroups: true, totalItemCount: 2,
          trophies: [
            { trophyId: 0, trophyHidden: false, trophyType: "platinum", trophyName: "All Trophies",
              trophyDetail: "Unlock every trophy", trophyIconUrl: "https://example.test/0.png", trophyGroupId: "default" },
            { trophyId: 1, trophyHidden: true, trophyType: "bronze", trophyName: "Secret",
              trophyDetail: "Find it", trophyIconUrl: "https://example.test/1.png", trophyGroupId: "001" }
          ]
        }))
    end

    it "merges definitions with the member's Unlocks, taking Rarity from the member endpoint" do
      stub_http(:get, earned_url, match: ->(request) { request[:params] == { "npServiceName" => "trophy2" } },
        reply: json({
          trophySetVersion: "01.10", totalItemCount: 2,
          trophies: [
            { trophyId: 0, trophyHidden: false, earned: false, trophyType: "platinum", trophyRare: 0, trophyEarnedRate: "1.2" },
            { trophyId: 1, trophyHidden: true, earned: true, earnedDateTime: "2026-10-30T21:15:04Z",
              trophyType: "bronze", trophyRare: 3, trophyEarnedRate: "54.7" }
          ]
        }))

      set = client.set_with_progress(account_id, np_comm_id, "trophy2")

      expect(set).to have_attributes(external_id: np_comm_id, np_service_name: "trophy2")
      expect(set.achievements).to eq([
        Achievements::Providers::AchievementDefinition.new(
          external_id: "0", name: "All Trophies", description: "Unlock every trophy",
          icon_url: "https://example.test/0.png", hidden: false, tier: "platinum", display_order: 0,
          rarity: BigDecimal("1.2")
        ),
        Achievements::Providers::AchievementDefinition.new(
          external_id: "1", name: "Secret", description: "Find it",
          icon_url: "https://example.test/1.png", hidden: true, tier: "bronze", display_order: 1,
          rarity: BigDecimal("54.7")
        )
      ])
      expect(set.unlocks).to eq([
        Achievements::Providers::ProviderUnlock.new(achievement_external_id: "1", unlocked_at: Time.utc(2026, 10, 30, 21, 15, 4))
      ])
    end

    it "treats a 404 on the member's trophies (never synced) as nothing earned" do
      stub_http(:get, earned_url, reply: json({ error: { code: 2_240_525, message: "Resource not found" } }, status: 404))

      set = client.set_with_progress(account_id, np_comm_id, "trophy2")

      expect(set.unlocks).to eq([])
      expect(set.achievements.map(&:external_id)).to eq(%w[0 1])
      expect(set.achievements.map(&:rarity)).to eq([ nil, nil ])
    end

    it "raises Private when the member's trophies are hidden" do
      stub_http(:get, earned_url, reply: json({ error: { code: 2_240_526, message: "Not permitted by access control" } }))

      expect { client.set_with_progress(account_id, np_comm_id, "trophy2") }
        .to raise_error(Achievements::Providers::Private)
    end
  end
end
