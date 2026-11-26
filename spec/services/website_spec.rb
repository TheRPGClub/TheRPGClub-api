# frozen_string_literal: true

require "rails_helper"

RSpec.describe Website do
  def with_address(value)
    stub_const("ENV", ENV.to_h.merge("DISCORD_OAUTH_SUCCESS_REDIRECT" => value))
  end

  it "reads the website's address from its sign-in callback" do
    with_address("https://therpg.club/auth/callback?x=1")

    expect(described_class.address.to_s).to eq("https://therpg.club/auth/callback?x=1")
    expect(described_class.url("/api/revalidate")).to eq("https://therpg.club/api/revalidate")
    expect(described_class.url("/feedback", pinned: 7, skip: nil)).to eq("https://therpg.club/feedback?pinned=7")
  end

  it "has no address when the setting is missing, relative or not a URL" do
    [ "", "/auth/callback", "ftp://therpg.club", "http://exa mple" ].each do |value|
      with_address(value)

      expect(described_class.address).to be_nil, value
      expect(described_class.url("/")).to be_nil
    end
  end
end
