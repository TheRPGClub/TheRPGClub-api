# frozen_string_literal: true

require "rails_helper"

# Feature Preferences and the staff show-Preview setting narrow what the
# website shows, never who can use a Feature (spec #347, ticket #352). The
# feature gate on endpoints asks `can_use?`, so a preference can never turn a
# request into a 404.
RSpec.describe Features::Access do
  let(:states) { Features.keys.index_with("live").merge("journals" => "preview") }

  it "lets a member use a Feature they hid, while not showing it" do
    access = described_class.new(staff: false, states: states, hidden: [ "reviews" ])

    expect(access.can_use?("reviews")).to be(true)
    expect(access.shown?("reviews")).to be(false)
  end

  it "lets staff with show-Preview off use a Preview Feature, while not showing it" do
    access = described_class.new(staff: true, states: states, show_preview: false)

    expect(access.can_use?("journals")).to be(true)
    expect(access.shown?("journals")).to be(false)
  end

  it "never hides a Core Feature, even if one were stored as hidden" do
    access = described_class.new(staff: false, states: states, hidden: [ "game_index" ])

    expect(access.shown?("game_index")).to be(true)
  end

  it "ignores the show-Preview setting for someone who is not staff" do
    access = described_class.new(staff: false, states: states, show_preview: false)

    expect(access.shown?("reviews")).to be(true)
    expect(access.can_use?("journals")).to be(false)
  end
end
