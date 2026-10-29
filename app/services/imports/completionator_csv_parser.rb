# frozen_string_literal: true

module Imports
  # Parses a Completionator export into import item attributes, ported from
  # the bot's parseCompletionatorCsv but with a real CSV parser (quoted
  # commas and multiline fields work):
  #
  #   rows = Imports::CompletionatorCsvParser.new.parse(csv_text)
  #   # => [{ row_index: 2, game_title: "Chrono Trigger", platform_name: "SNES",
  #   #       region_name: nil, source_type: "Core Game", time_text: "25h:30m:00s",
  #   #       completed_at: Date(2021-03-07), completion_type: "Main Story",
  #   #       playtime_hrs: 25.5 }, ...]
  #
  # The first record is a header and is skipped. Columns are positional:
  # name, platform, region, type, time, date. Records with fewer than 6
  # fields or a blank name are dropped. `row_index` is the 1-based physical
  # line the record starts on (Imports::CsvRecords), so the header is 1, as
  # for the collection CSV.
  #
  # - type: TYPE_MAP (case-insensitive), nil when unknown.
  # - time: "Hh:Mm:Ss" -> hours rounded to 2 decimals (seconds ignored).
  # - date: "M/D/YYYY" -> Date.
  # An unparseable time or date is nil; the raw text stays in `time_text`.
  #
  # Raises InvalidCsv on malformed CSV or when no data row remains.
  class CompletionatorCsvParser
    class InvalidCsv < StandardError; end

    TYPE_MAP = {
      "core game" => "Main Story",
      "core game (+ a few extras)" => "Main Story + Side Content",
      "core game (+ lots of extras)" => "Main Story + Side Content",
      "completionated" => "Completionist"
    }.freeze
    MIN_FIELDS = 6

    def self.map_type(value)
      TYPE_MAP[value.to_s.strip.downcase]
    end

    def parse(text)
      records = CsvRecords.parse(text).drop_while { |record| record.fields.empty? }
      rows = records.drop(1).filter_map { |record| build_row(record.fields, record.line) }
      raise InvalidCsv, "The CSV has no data rows." if rows.empty?

      rows
    rescue CsvRecords::Malformed => error
      raise InvalidCsv, error.message
    end

    private

    def build_row(fields, row_index)
      return if fields.size < MIN_FIELDS

      name, platform, region, type, time, date = fields.first(MIN_FIELDS).map { |field| field.to_s.strip.presence }
      return if name.nil?

      {
        row_index: row_index, game_title: name, platform_name: platform, region_name: region,
        source_type: type, time_text: time, completed_at: parse_date(date),
        completion_type: self.class.map_type(type), playtime_hrs: parse_time(time)
      }
    end

    def parse_time(value)
      match = value.to_s.match(/(\d+)h:(\d+)m:(\d+)s/i)
      return unless match

      (match[1].to_i + (match[2].to_i / 60.0)).round(2)
    end

    def parse_date(value)
      match = value.to_s.match(%r{\A(\d{1,2})/(\d{1,2})/(\d{4})\z})
      return unless match

      Date.new(match[3].to_i, match[1].to_i, match[2].to_i)
    rescue Date::Error
      nil
    end
  end
end
