# frozen_string_literal: true

require "rails_helper"

# The Club Codex entries table holds all three parts (spec #397, ticket #404),
# so the Lore Entry and History Event tickets add endpoints without changing
# it. Each part's shape is held by the table itself.
RSpec.describe CodexEntry do
  let(:author) { create(:user) }

  def insert(**attrs)
    described_class.insert_all!([ { author_user_id: author.user_id, created_at: Time.current,
                                    updated_at: Time.current }.merge(attrs) ])
  end

  it "stores a History Event, a Lore Entry and a Fun Fact" do
    insert(part: "history_event", title: "The club moves to Discord", occurred_on: Date.new(2018, 3, 1),
      date_precision: "month", kind: "platform", rich_body: { "type" => "p" }, body: "We moved.")
    insert(part: "history_event", title: "Founded", occurred_on: Date.new(2016, 1, 1), date_precision: "year",
      kind: "founding")
    insert(part: "lore_entry", title: "The #general wipe", rich_body: [ { "type" => "p" } ], body: "It happened.")
    insert(part: "lore_entry", title: "The bake-off", body: "Cakes.", occurred_on: Date.new(2020, 5, 14),
      date_precision: "day")
    insert(part: "fun_fact", body: "Rhea named the bot.", last_shown_at: Time.current)

    expect(described_class.group(:part).count).to eq("history_event" => 2, "lore_entry" => 2, "fun_fact" => 1)
  end

  {
    "an unknown part" => { part: "rumour", body: "Shh." },
    "a History Event without a kind" => { part: "history_event", title: "T", occurred_on: Date.new(2016, 1, 1),
                                          date_precision: "year" },
    "an unknown History Event Kind" => { part: "history_event", title: "T", occurred_on: Date.new(2016, 1, 1),
                                         date_precision: "year", kind: "gossip" },
    "a History Event without a date" => { part: "history_event", title: "T", kind: "staff" },
    "a kind on a Lore Entry" => { part: "lore_entry", title: "T", body: "B", kind: "staff" },
    "a Lore Entry without a title" => { part: "lore_entry", body: "B" },
    "a Lore Entry without a body" => { part: "lore_entry", title: "T" },
    "a rich body without its Discord text" => { part: "history_event", title: "T", occurred_on: Date.new(2016, 1, 1),
                                                date_precision: "year", kind: "staff", rich_body: { "type" => "p" } },
    "a date without a precision" => { part: "lore_entry", title: "T", body: "B", occurred_on: Date.new(2020, 5, 14) },
    "a precision without a date" => { part: "lore_entry", title: "T", body: "B", date_precision: "day" },
    "a month date not on the first" => { part: "lore_entry", title: "T", body: "B", occurred_on: Date.new(2020, 5, 14),
                                         date_precision: "month" },
    "a year date not on 1 January" => { part: "lore_entry", title: "T", body: "B", occurred_on: Date.new(2020, 5, 1),
                                        date_precision: "year" },
    "a title on a Fun Fact" => { part: "fun_fact", title: "T", body: "B" },
    "a Fun Fact over 300 characters" => { part: "fun_fact", body: "a" * 301 },
    "a date on a Fun Fact" => { part: "fun_fact", body: "B", occurred_on: Date.new(2020, 5, 14), date_precision: "day" },
    "a rich body on a Fun Fact" => { part: "fun_fact", body: "B", rich_body: { "type" => "p" } },
    "a last shown time on a Lore Entry" => { part: "lore_entry", title: "T", body: "B", last_shown_at: Time.current }
  }.each do |description, attrs|
    it "refuses #{description}" do
      expect { insert(**attrs) }.to raise_error(ActiveRecord::StatementInvalid)
    end
  end
end
