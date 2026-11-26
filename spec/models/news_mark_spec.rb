# frozen_string_literal: true

require "rails_helper"

# The News Mark (spec api#494, ticket api#495) for a member the API has no
# rpg_club_users row for yet. A session request cannot reach this state (the
# session token's member must exist), so it is covered here at the model.
RSpec.describe NewsMark do
  let(:user_id) { SecureRandom.random_number(10**18).to_s }
  let(:now) { Time.zone.parse("2026-11-26 18:00:00 UTC") }

  it "has no News Mark for a member with no row" do
    expect(described_class.for(user_id)).to be_nil
  end

  it "creates the member's row and stores the News Mark rather than dropping it" do
    mark = described_class.advance!(user_id, Time.zone.parse("2026-11-24 21:40:00 UTC"), now: now)

    expect(mark).to eq(Time.zone.parse("2026-11-24 21:40:00 UTC"))
    expect(described_class.for(user_id)).to eq(Time.zone.parse("2026-11-24 21:40:00 UTC"))
    expect(RpgClubUser.exists?(user_id: user_id)).to be(true)
  end
end
