# frozen_string_literal: true

require "rails_helper"

# Playtime::Playthroughs (spec api#457, ticket api#459): a Playthrough a Game
# Completion just closed stays closed, even when an abandon or a set total
# read it while it was still open.
RSpec.describe Playtime::Playthroughs do
  let(:member) { create(:user) }
  let(:game) { create(:game) }
  let!(:playthrough) { create(:playthrough, user: member, game: game) }

  # The copy a request read before the Completion's transaction closed it.
  let!(:stale) { UserGamePlaythrough.find(playthrough.id) }

  before do
    completion = create(:completion, user: member, game: game)
    playthrough.update!(ended_at: Time.current, end_reason: "completed", completion_id: completion.completion_id,
      final_minutes: 120)
  end

  it "refuses to abandon one a Completion closed meanwhile" do
    expect { described_class.abandon!(stale) }.to raise_error(described_class::Closed)

    expect(playthrough.reload).to have_attributes(end_reason: "completed", final_minutes: 120,
      completion_id: be_present)
  end

  it "refuses to set the total of one a Completion closed meanwhile" do
    expect { described_class.set_total!(stale, 300) }.to raise_error(described_class::Closed)

    expect(playthrough.reload).to have_attributes(manual_total_minutes: nil, end_reason: "completed")
  end
end
