# frozen_string_literal: true

require "rails_helper"

RSpec.describe AchievementHubState do
  it "returns nil for an unset key" do
    expect(described_class.get("highlight_cursor")).to be_nil
  end

  it "stores and overwrites a JSON value per key" do
    described_class.set("highlight_cursor", { "last_id" => 10 })
    described_class.set("highlight_cursor", { "last_id" => 42 })

    expect(described_class.get("highlight_cursor")).to eq("last_id" => 42)
    expect(described_class.where(key: "highlight_cursor").count).to eq(1)
  end

  it "stores a scalar value" do
    described_class.set("psn_auth_expired_at", "2026-11-01T12:00:00Z")

    expect(described_class.get("psn_auth_expired_at")).to eq("2026-11-01T12:00:00Z")
  end

  it "clears a value with nil" do
    described_class.set("psn_auth_expired_at", "2026-11-01T12:00:00Z")
    described_class.set("psn_auth_expired_at", nil)

    expect(described_class.get("psn_auth_expired_at")).to be_nil
  end
end
