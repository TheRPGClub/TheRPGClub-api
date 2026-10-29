# frozen_string_literal: true

require "rails_helper"

# The collection CSV template parser (the bot's parseCollectionCsvImportText):
# header aliases, row validation, and whole-file rejection on any error.
RSpec.describe Imports::CollectionCsvParser do
  subject(:parser) { described_class.new(platform_resolver: Imports::PlatformResolver.new) }

  let!(:platform) { create(:platform, platform_name: "Csvparse Station #{SecureRandom.hex(3)}", platform_abbreviation: "CSVP#{SecureRandom.hex(2)}") }

  it "parses valid rows with their 1-based CSV line as row_index" do
    csv = <<~CSV
      title,platform,ownership_type,note,gamedb_id,igdb_id
      Chrono Trigger,#{platform.platform_name},physical,"boxed, mint",,
      Suikoden II,,,,42,
      Xenogears,,Subscription,,,1234
    CSV

    result = parser.parse(csv)

    expect(result.errors).to eq([])
    expect(result.rows.map(&:row_index)).to eq([ 2, 3, 4 ])
    expect(result.rows.first).to have_attributes(
      title: "Chrono Trigger", raw_platform: platform.platform_name, platform_id: platform.platform_id,
      raw_ownership_type: "physical", ownership_type: "Physical", raw_note: "boxed, mint",
      gamedb_id: nil, igdb_id: nil
    )
    expect(result.rows.second).to have_attributes(raw_platform: nil, platform_id: nil, ownership_type: "Digital", gamedb_id: 42)
    expect(result.rows.third).to have_attributes(ownership_type: "Subscription", igdb_id: 1234)
  end

  it "accepts header aliases and strips a BOM, skipping blank and example rows" do
    csv = "﻿Game Name,Notes,IGDB\r\n" \
          "Example Game,EXAMPLE ROW - DELETE BEFORE IMPORT,\r\n" \
          ",,\r\n" \
          "Real Game,\"multi\nline\",\r\n"

    result = parser.parse(csv)

    expect(result.errors).to eq([])
    expect(result.rows.map { |row| [ row.row_index, row.title ] }).to eq([ [ 4, "Real Game" ] ])
    expect(result.rows.sole.raw_note).to eq("multi line")
  end

  it "numbers rows by the physical line they start on when a quoted field spans lines" do
    valid = "title,note\n\"Two\nLine Title\",\"a\nb\nc\"\nNext,\n"

    expect(parser.parse(valid).rows.map { |row| [ row.row_index, row.title ] })
      .to eq([ [ 2, "Two Line Title" ], [ 6, "Next" ] ])
    expect(parser.parse("#{valid},a note\n").errors.map { |error| [ error[:row_index], error[:column] ] })
      .to eq([ [ 7, "title" ] ])
  end

  it "reports an unterminated quoted field at the physical line it starts on" do
    result = parser.parse("title,note\n\"A\nB\",x\n\"Broken,oops\n")

    expect(result.errors.sole).to eq(row_index: 4, column: "file", message: "Unterminated quoted field.")
  end

  it "rejects the whole file with one error per bad cell" do
    csv = <<~CSV
      title,platform,ownership_type,note,gamedb_id,igdb_id
      ,,,,,
      Good Row,,,,,
      ,Nowhere Console 9000,Borrowed,#{'x' * 501},abc,-3
      Both Ids,,,,5,6
    CSV

    result = parser.parse(csv)

    expect(result.rows).to eq([])
    expect(result.errors.map { |error| [ error[:row_index], error[:column] ] }).to eq([
      [ 4, "title" ], [ 4, "gamedb_id" ], [ 4, "igdb_id" ], [ 4, "ownership_type" ], [ 4, "note" ], [ 4, "platform" ],
      [ 5, "gamedb_id" ]
    ])
    expect(result.errors.first[:message]).to eq("Title is required.")
  end

  it "requires a title column" do
    result = parser.parse("platform,note\nSNES,hi\n")

    expect(result.errors).to eq([ { row_index: 1, column: "title", message: 'Missing required column "title".' } ])
  end

  it "reports an empty file and a file with no importable rows" do
    expect(parser.parse("").errors).to eq([ { row_index: 1, column: "file", message: "CSV file is empty." } ])
    expect(parser.parse("title\n\n").errors)
      .to eq([ { row_index: 1, column: "file", message: "CSV file contains no importable rows." } ])
  end

  it "reports an unterminated quoted field" do
    result = parser.parse("title,note\n\"Broken,oops\n")

    expect(result.rows).to eq([])
    expect(result.errors.sole).to eq(row_index: 2, column: "file", message: "Unterminated quoted field.")
  end
end
