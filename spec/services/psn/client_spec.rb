# frozen_string_literal: true

require "rails_helper"

RSpec.describe Psn::Client do
  include ActiveSupport::Testing::TimeHelpers

  subject(:client) do
    described_class.new(npsso: "test-npsso", cache: cache, hub_state: hub_state, sleeper: ->(seconds) { sleeps << seconds })
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

  def json(body = {}, status: 200, headers: {})
    { status: status, body: body.to_json, headers: { "Content-Type" => "application/json" }.merge(headers) }
  end

  def stub_authorize(location: redirect_with_code)
    stub_request(:get, described_class::AUTHORIZE_URL)
      .with(query: hash_including("client_id" => described_class::OAUTH_CLIENT_ID, "response_type" => "code"),
        headers: { "Cookie" => "npsso=test-npsso" })
      .to_return(status: 302, headers: { "Location" => location })
  end

  def stub_code_exchange(access_token: "access-1", refresh_token: "refresh-1")
    stub_request(:post, described_class::TOKEN_URL)
      .with(body: hash_including("grant_type" => "authorization_code", "code" => "v3.AUTHCODE"),
        headers: { "Authorization" => described_class::CLIENT_AUTH })
      .to_return(json({ access_token: access_token, expires_in: 3599, refresh_token: refresh_token,
        refresh_token_expires_in: 5_183_999, token_type: "bearer" }))
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
    stub_request(:get, titles_url)
      .with(query: { "limit" => described_class::TITLES_PAGE.to_s, "offset" => offset.to_s },
        headers: { "Authorization" => "Bearer #{token}" })
      .to_return(json({ trophyTitles: rows, totalItemCount: total }))
  end

  describe "auth" do
    it "exchanges the NPSSO for an access token and caches it" do
      stub_authorize
      stub_code_exchange
      titles = stub_titles([])

      client.played_sets(account_id)
      client.played_sets(account_id)

      expect(a_request(:get, described_class::AUTHORIZE_URL).with(query: hash_including({}))).to have_been_made.once
      expect(titles).to have_been_made.twice
    end

    it "renews an expired access token with the cached refresh token instead of the NPSSO" do
      stub_authorize
      stub_code_exchange
      stub_titles([])
      refresh = stub_request(:post, described_class::TOKEN_URL)
        .with(body: hash_including("grant_type" => "refresh_token", "refresh_token" => "refresh-1"))
        .to_return(json({ access_token: "access-2", expires_in: 3599, refresh_token: "refresh-2",
          refresh_token_expires_in: 5_183_999 }))
      second = stub_titles([], token: "access-2")

      client.played_sets(account_id)
      travel(3600.seconds) { client.played_sets(account_id) }

      expect(refresh).to have_been_made.once
      expect(second).to have_been_made.once
      expect(a_request(:get, described_class::AUTHORIZE_URL).with(query: hash_including({}))).to have_been_made.once
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

    it "raises AuthExpired when Sony refuses the code exchange" do
      stub_authorize
      stub_request(:post, described_class::TOKEN_URL).to_return(json({ error: "invalid_grant" }, status: 400))

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
          last_played_at: Time.utc(2026, 10, 30, 12),
          earned_count: 6,
          total_count: 15
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
      expect(a_request(:get, titles_url).with(query: hash_including("offset" => "3"))).not_to have_been_made
    end

    it "raises Private on Sony's access-control error, even with HTTP 200" do
      stub_request(:get, titles_url).with(query: hash_including({}))
        .to_return(json({ error: { referenceId: "abc", code: 2_240_526, message: "Not permitted by access control" } }))

      expect { client.played_sets(account_id) }.to raise_error(Achievements::Providers::Private)
    end

    it "raises Private on a 403 access-control error" do
      stub_request(:get, titles_url).with(query: hash_including({}))
        .to_return(json({ error: { code: 2_240_526, message: "Not permitted by access control" } }, status: 403))

      expect { client.played_sets(account_id) }.to raise_error(Achievements::Providers::Private)
    end

    it "raises NotFound for an unknown accountId" do
      stub_request(:get, titles_url).with(query: hash_including({}))
        .to_return(json({ error: { code: 2_240_525, message: "Resource not found" } }, status: 404))

      expect { client.played_sets(account_id) }.to raise_error(Achievements::Providers::NotFound)
    end

    it "raises RateLimited on 429, carrying Retry-After" do
      stub_request(:get, titles_url).with(query: hash_including({}))
        .to_return(status: 429, headers: { "Retry-After" => "3" })

      expect { client.played_sets(account_id) }
        .to raise_error(Achievements::Providers::RateLimited) { |error| expect(error.retry_after).to eq(3.0) }
    end

    it "retries once after an SSL EOF" do
      stub_request(:get, titles_url).with(query: hash_including({}))
        .to_raise(OpenSSL::SSL::SSLError.new("SSL_read: unexpected eof while reading")).then
        .to_return(json({ trophyTitles: [ title_row("NPWR1_00", "2026-10-30T12:00:00Z") ], totalItemCount: 1 }))

      expect(client.played_sets(account_id).map(&:external_id)).to eq(%w[NPWR1_00])
    end

    it "retries a transient 5xx with a short backoff" do
      stub_request(:get, titles_url).with(query: hash_including({}))
        .to_return(status: 503).then
        .to_return(json({ trophyTitles: [], totalItemCount: 0 }))

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
      stub_request(:post, described_class::SEARCH_URL)
        .with(body: hash_including("searchTerm" => "Xergg", "domainRequests" => [ { "domain" => "SocialAllAccounts" } ]))
        .to_return(json({ domainResponses: [ { domain: "SocialAllAccounts", results: results } ] }))
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
      stub_request(:get, format(described_class::PROFILE_URL, "Xergg")).with(query: hash_including({}))
        .to_return(json({ profile: { onlineId: "Xergg", accountId: account_id,
                                     avatarUrls: [ { size: "l", avatarUrl: "https://example.test/a.png" } ] } }))

      expect(client.resolve_account("Xergg")).to eq(
        external_id: account_id, display_name: "Xergg", avatar_url: "https://example.test/a.png"
      )
    end

    it "raises NotFound for an unknown online ID" do
      stub_search
      stub_request(:get, format(described_class::PROFILE_URL, "Xergg")).with(query: hash_including({}))
        .to_return(json({ error: { code: 2_105_356, message: "User not found" } }, status: 404))

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
      stub_request(:get, definitions_url).with(query: { "npServiceName" => "trophy2" })
        .to_return(json({
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
      stub_request(:get, earned_url).with(query: { "npServiceName" => "trophy2" })
        .to_return(json({
          trophySetVersion: "01.10", totalItemCount: 2,
          trophies: [
            { trophyId: 0, trophyHidden: false, earned: false, trophyType: "platinum", trophyRare: 0, trophyEarnedRate: "1.2" },
            { trophyId: 1, trophyHidden: true, earned: true, earnedDateTime: "2026-10-30T21:15:04Z",
              trophyType: "bronze", trophyRare: 3, trophyEarnedRate: "54.7" }
          ]
        }))

      set = client.set_with_progress(account_id, np_comm_id, "trophy2")

      expect(set).to have_attributes(external_id: np_comm_id, np_service_name: "trophy2", version: "01.10")
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
      stub_request(:get, earned_url).with(query: hash_including({}))
        .to_return(json({ error: { code: 2_240_525, message: "Resource not found" } }, status: 404))

      set = client.set_with_progress(account_id, np_comm_id, "trophy2")

      expect(set.unlocks).to eq([])
      expect(set.achievements.map(&:external_id)).to eq(%w[0 1])
      expect(set.achievements.map(&:rarity)).to eq([ nil, nil ])
    end

    it "raises Private when the member's trophies are hidden" do
      stub_request(:get, earned_url).with(query: hash_including({}))
        .to_return(json({ error: { code: 2_240_526, message: "Not permitted by access control" } }))

      expect { client.set_with_progress(account_id, np_comm_id, "trophy2") }
        .to raise_error(Achievements::Providers::Private)
    end
  end
end
