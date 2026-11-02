# frozen_string_literal: true

require "rails_helper"

RSpec.describe Auth::DiscordOauthClient do
  subject(:client) { described_class.new(http: http) }

  let(:stubs) { Faraday::Adapter::Test::Stubs.new }
  let(:http) { Faraday.new { |builder| builder.adapter(:test, stubs) } }
  let(:guild_id) { "123456789012345678" }

  around do |example|
    saved = %w[DISCORD_RPGCLUB_GUILD_ID DISCORD_OAUTH_SCOPES].to_h { |key| [ key, ENV.fetch(key, nil) ] }
    ENV["DISCORD_RPGCLUB_GUILD_ID"] = guild_id
    ENV["DISCORD_OAUTH_SCOPES"] = "identify email guilds guilds.members.read"
    example.run
  ensure
    saved.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  def json(status: 200, body: {})
    [ status, { "Content-Type" => "application/json" }, body.to_json ]
  end

  describe "#fetch_rpgclub_member_roles!" do
    it "returns the member's role IDs in the club guild as strings" do
      stubs.get("https://discord.com/api/users/@me/guilds/#{guild_id}/member") do |env|
        expect(env.request_headers["Authorization"]).to eq("Bearer user-access-token")
        json(body: { roles: [ "461891227613265940", 747_520_789_003_239_530 ], nick: "Member" })
      end

      expect(client.fetch_rpgclub_member_roles!("user-access-token"))
        .to eq(%w[461891227613265940 747520789003239530])
      stubs.verify_stubbed_calls
    end

    it "returns no roles when Discord omits the roles list" do
      stubs.get("https://discord.com/api/users/@me/guilds/#{guild_id}/member") { json(body: { nick: "Member" }) }

      expect(client.fetch_rpgclub_member_roles!("user-access-token")).to eq([])
    end

    it "raises with Discord's message when the lookup is rejected" do
      stubs.get("https://discord.com/api/users/@me/guilds/#{guild_id}/member") do
        json(status: 401, body: { message: "401: Unauthorized", code: 0 })
      end

      expect { client.fetch_rpgclub_member_roles!("expired-token") }
        .to raise_error(StandardError, "401: Unauthorized")
    end

    it "refuses to call Discord without the guilds.members.read scope" do
      ENV["DISCORD_OAUTH_SCOPES"] = "identify email guilds"

      expect { client.fetch_rpgclub_member_roles!("user-access-token") }
        .to raise_error(described_class::ConfigurationError, /guilds\.members\.read/)
    end
  end
end
