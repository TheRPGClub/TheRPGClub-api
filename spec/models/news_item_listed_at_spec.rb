# frozen_string_literal: true

require "rails_helper"

# `listed_at` (spec api#494, code-review fix pass): the moment a News Item
# first had a News Category, which is when members could first see it. The
# News Mark counts News Items listed after it as new, so an item the bot
# records late (catch-up after downtime) is still new to everyone.
RSpec.describe NewsItem, "listed_at" do
  include ActiveSupport::Testing::TimeHelpers

  let(:recorded_at) { Time.zone.parse("2026-11-26 18:00:00 UTC") }

  def payload(**overrides)
    { "channel_id" => "1", "author_id" => "2", "author_name" => "Kestrel", "category_key" => "releases",
      "posted_at" => "2026-11-20T10:00:00Z", "link" => { "url" => "https://example.com/a" } }.merge(overrides)
  end

  it "is when a live News Item is first recorded, however long before that it was posted" do
    item, = travel_to(recorded_at) { described_class.record!("100", payload) }

    expect(item.reload.listed_at).to eq(recorded_at)
    expect(item.posted_at).to eq(Time.zone.parse("2026-11-20 10:00:00 UTC"))
  end

  it "keeps its first value when the News Item is recorded again or changes News Category" do
    item, = travel_to(recorded_at) { described_class.record!("100", payload) }
    travel_to(recorded_at + 1.day) do
      described_class.record!("100", payload("comment" => "edited"))
      item.reload.change_category!("industry", by: "3")
    end

    expect(item.reload.listed_at).to eq(recorded_at)
  end

  it "is empty for an imported News Item staff have not sorted" do
    item = create(:news_item, origin: "import", category_key: nil)

    expect(item.reload.listed_at).to be_nil
  end

  it "is when staff sort an imported News Item with a News Import upload" do
    item = create(:news_item, origin: "import", category_key: nil)
    travel_to(recorded_at) { NewsImport::Assign.call([ { "message_id" => item.message_id, "value" => "general" } ], by: "3") }

    expect(item.reload.listed_at).to eq(recorded_at)
  end

  it "keeps its first value when staff sort an imported News Item again" do
    item = create(:news_item, origin: "import", category_key: nil)
    travel_to(recorded_at) { NewsImport::Assign.call([ { "message_id" => item.message_id, "value" => "general" } ], by: "3") }
    travel_to(recorded_at + 1.day) do
      NewsImport::Assign.call([ { "message_id" => item.message_id, "value" => "industry" } ], by: "3")
    end

    expect(item.reload).to have_attributes(category_key: "industry", listed_at: recorded_at)
  end
end
