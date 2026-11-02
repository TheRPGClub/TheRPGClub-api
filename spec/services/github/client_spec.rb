# frozen_string_literal: true

require "rails_helper"

RSpec.describe Github::Client do
  subject(:client) do
    described_class.new(app_id: "12345", installation_id: "678", private_key: pem, http: http, clock: -> { now })
  end

  let(:rsa_key) { OpenSSL::PKey::RSA.new(2048) }
  let(:pem) { rsa_key.to_pem }
  let(:now) { Time.utc(2026, 11, 2, 12, 0, 0) }
  let(:stubs) { Faraday::Adapter::Test::Stubs.new }
  let(:http) { Faraday.new(url: described_class::API_BASE) { |builder| builder.adapter(:test, stubs) } }
  let(:token_path) { "/app/installations/678/access_tokens" }

  before { described_class.reset_token_cache! }

  def json_response(status, body)
    [ status, { "Content-Type" => "application/json" }, body.to_json ]
  end

  def stub_token(token: "inst-token", expires_at: now + 1.hour)
    stubs.post(token_path) { json_response(201, token: token, expires_at: expires_at.iso8601) }
  end

  def decode_segment(segment)
    JSON.parse(Base64.urlsafe_decode64(segment + ("=" * ((4 - (segment.length % 4)) % 4))))
  end

  describe "#create_issue" do
    it "signs an app JWT, trades it for an installation token, then creates the issue" do
      stubs.post(token_path) do |env|
        jwt = env.request_headers["Authorization"].delete_prefix("Bearer ")
        header, payload, signature = jwt.split(".")
        expect(decode_segment(header)).to eq("alg" => "RS256", "typ" => "JWT")
        expect(decode_segment(payload)).to eq("iat" => now.to_i - 60, "exp" => now.to_i + 540, "iss" => 12_345)
        signed = rsa_key.public_key.verify(
          OpenSSL::Digest.new("SHA256"),
          Base64.urlsafe_decode64(signature + ("=" * ((4 - (signature.length % 4)) % 4))),
          "#{header}.#{payload}"
        )
        expect(signed).to be(true)
        expect(env.request_headers["X-GitHub-Api-Version"]).to eq("2022-11-28")
        json_response(201, token: "inst-token", expires_at: (now + 1.hour).iso8601)
      end
      stubs.post("/repos/TheRPGClub/TheRPGClub-www/issues") do |env|
        expect(env.request_headers["Authorization"]).to eq("token inst-token")
        expect(JSON.parse(env.body)).to eq("title" => "Dark mode", "body" => "tester: Please", "labels" => [ "Bug" ])
        json_response(201, number: 42, html_url: "https://github.com/TheRPGClub/TheRPGClub-www/issues/42", state: "open")
      end

      issue = client.create_issue(repo: "TheRPGClub/TheRPGClub-www", title: "Dark mode", body: "tester: Please",
        labels: [ "Bug" ])

      expect(issue.to_h).to eq(number: 42, url: "https://github.com/TheRPGClub/TheRPGClub-www/issues/42", state: "open")
      stubs.verify_stubbed_calls
    end

    it "reuses the installation token until a minute before it expires" do
      calls = 0
      stubs.post(token_path) do
        calls += 1
        json_response(201, token: "inst-token", expires_at: (now + 1.hour).iso8601)
      end
      stubs.post("/repos/TheRPGClub/TheRPGClub-bot/issues") { json_response(201, number: 1, html_url: "u", state: "open") }

      2.times { client.create_issue(repo: "TheRPGClub/TheRPGClub-bot", title: "t", body: "b") }

      expect(calls).to eq(1)
    end

    it "accepts a private key with literal \\n escapes, as stored in a Fly secret" do
      escaped = described_class.new(app_id: "12345", installation_id: "678", private_key: pem.gsub("\n", "\\n"),
        http: http, clock: -> { now })
      stub_token
      stubs.post("/repos/TheRPGClub/TheRPGClub-api/issues") { json_response(201, number: 7, html_url: "u", state: "open") }

      expect(escaped.create_issue(repo: "TheRPGClub/TheRPGClub-api", title: "t", body: "b").number).to eq(7)
    end

    it "raises RequestError with GitHub's message when the create fails" do
      stub_token
      stubs.post("/repos/TheRPGClub/TheRPGClub-api/issues") { json_response(422, message: "Validation Failed") }

      expect { client.create_issue(repo: "TheRPGClub/TheRPGClub-api", title: "t", body: "b") }
        .to raise_error(described_class::RequestError, /422.*Validation Failed/)
    end

    it "raises RequestError when the token exchange fails" do
      stubs.post(token_path) { json_response(401, message: "Bad credentials") }

      expect { client.create_issue(repo: "TheRPGClub/TheRPGClub-api", title: "t", body: "b") }
        .to raise_error(described_class::RequestError, /401.*Bad credentials/)
    end

    it "raises RequestError on a connection failure" do
      stubs.post(token_path) { raise Faraday::ConnectionFailed, "down" }

      expect { client.create_issue(repo: "TheRPGClub/TheRPGClub-api", title: "t", body: "b") }
        .to raise_error(described_class::RequestError, /down/)
    end

    it "raises ConfigurationError naming the missing settings" do
      unconfigured = described_class.new(app_id: "", installation_id: "678", private_key: "", http: http)

      expect { unconfigured.create_issue(repo: "TheRPGClub/TheRPGClub-api", title: "t", body: "b") }
        .to raise_error(described_class::ConfigurationError, /GITHUB_APP_ID.*GITHUB_APP_PRIVATE_KEY/)
    end
  end

  describe "#issue_state" do
    it "returns open or closed" do
      stub_token
      stubs.get("/repos/TheRPGClub/TheRPGClub-bot/issues/5") { json_response(200, number: 5, state: "closed") }
      stubs.get("/repos/TheRPGClub/TheRPGClub-bot/issues/6") { json_response(200, number: 6, state: "open") }

      expect(client.issue_state(repo: "TheRPGClub/TheRPGClub-bot", number: 5)).to eq("closed")
      expect(client.issue_state(repo: "TheRPGClub/TheRPGClub-bot", number: 6)).to eq("open")
    end

    it "returns nil for a missing issue" do
      stub_token
      stubs.get("/repos/TheRPGClub/TheRPGClub-bot/issues/9") { json_response(404, message: "Not Found") }

      expect(client.issue_state(repo: "TheRPGClub/TheRPGClub-bot", number: 9)).to be_nil
    end

    it "raises RequestError for other failures" do
      stub_token
      stubs.get("/repos/TheRPGClub/TheRPGClub-bot/issues/9") { json_response(500, message: "boom") }

      expect { client.issue_state(repo: "TheRPGClub/TheRPGClub-bot", number: 9) }
        .to raise_error(described_class::RequestError)
    end
  end

  describe "#configured?" do
    it "is true only when the app id, installation id and private key are all set" do
      expect(described_class.new(app_id: "1", installation_id: "2", private_key: "k")).to be_configured
      expect(described_class.new(app_id: "1", installation_id: "", private_key: "k")).not_to be_configured
    end
  end
end
