# frozen_string_literal: true

require "rails_helper"

# Fixtures ported from the bot's parseCompletionatorCsv (positional columns
# name, platform, region, type, time, date; header skipped; short rows
# dropped), parsed with a real CSV parser so quoted commas and multiline
# fields survive.
RSpec.describe Imports::CompletionatorCsvParser do
  subject(:parse) { described_class.new.parse(csv) }

  let(:header) { "Name,Platform,Region,Type,Time,Date\n" }

  context "with a well-formed export" do
    let(:csv) do
      header +
        "Chrono Trigger,Super Nintendo,North America,Core Game,25h:30m:00s,3/7/2021\n" \
        "\"Final Fantasy VII, Remake\",PlayStation 4,,Core Game (+ a few extras),40h:20m:10s,12/25/2020\n" \
        "Hollow Knight,PC,,Completionated,,\n"
    end

    it "maps each data row, numbering rows by physical line (the header is 1)" do
      expect(parse.size).to eq(3)
      expect(parse.first).to eq(
        row_index: 2, game_title: "Chrono Trigger", platform_name: "Super Nintendo",
        region_name: "North America", source_type: "Core Game", time_text: "25h:30m:00s",
        completed_at: Date.new(2021, 3, 7), completion_type: "Main Story", playtime_hrs: 25.5
      )
    end

    it "keeps quoted commas inside a field" do
      expect(parse.second).to include(
        row_index: 3, game_title: "Final Fantasy VII, Remake", region_name: nil,
        completion_type: "Main Story + Side Content", playtime_hrs: 40.33, completed_at: Date.new(2020, 12, 25)
      )
    end

    it "leaves blank time and date as nil" do
      expect(parse.third).to include(
        game_title: "Hollow Knight", completion_type: "Completionist",
        time_text: nil, playtime_hrs: nil, completed_at: nil
      )
    end
  end

  it "maps the lots-of-extras type and leaves unknown types nil" do
    rows = described_class.new.parse(
      header + "A,PC,,Core Game (+ lots of extras),1h:00m:00s,1/1/2020\nB,PC,,Speedrun,1h:00m:00s,1/1/2020\n"
    )

    expect(rows.map { |row| row[:completion_type] }).to eq([ "Main Story + Side Content", nil ])
  end

  it "supports a quoted multiline field and a BOM, and skips blank and short rows" do
    rows = described_class.new.parse(
      "﻿#{header}\n\"Multi\nLine\",PC,,Core Game,,\nshort,row\n,PC,,Core Game,,\n"
    )

    expect(rows.map { |row| row[:game_title] }).to eq([ "Multi\nLine" ])
  end

  it "numbers rows by the physical line they start on, past blank lines and multiline fields" do
    rows = described_class.new.parse(
      "#{header}\n\"Multi\nLine\",PC,,Core Game,,\nshort,row\nAfter,PC,,Core Game,,\n"
    )

    expect(rows.map { |row| [ row[:row_index], row[:game_title] ] }).to eq([ [ 3, "Multi\nLine" ], [ 6, "After" ] ])
  end

  it "ignores an unparseable date or time" do
    rows = described_class.new.parse(header + "A,PC,,Core Game,about 3 hours,2021-03-07\n")

    expect(rows.first).to include(completed_at: nil, playtime_hrs: nil, time_text: "about 3 hours")
  end

  it "raises InvalidCsv on malformed CSV" do
    expect { described_class.new.parse(header + "\"unterminated,PC,,Core Game,,\n") }
      .to raise_error(described_class::InvalidCsv)
  end

  it "raises InvalidCsv when there are no data rows" do
    expect { described_class.new.parse(header) }.to raise_error(described_class::InvalidCsv, /no data rows/)
  end
end
