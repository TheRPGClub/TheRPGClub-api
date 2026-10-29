# frozen_string_literal: true

require "csv"

module Imports
  # Parses and validates a collection CSV import file, ported from the bot's
  # parseCollectionCsvImportText. Template columns: title, platform,
  # ownership_type, note, gamedb_id, igdb_id. Only `title` is required.
  #
  #   result = Imports::CollectionCsvParser.new(platform_resolver: resolver).parse(csv_text)
  #   result.ok?     # => true when there are no errors
  #   result.rows    # => [Row(row_index:, title:, raw_platform:, platform_id:, ...)]
  #   result.errors  # => [{row_index:, column:, message:}]
  #
  # Like the bot, any error rejects the whole file (rows is then []). Header
  # names are normalised (lowercase, spaces/dashes to `_`) and mapped through
  # HEADER_ALIASES. Blank rows and rows whose note contains "EXAMPLE ROW" are
  # skipped. `row_index` is the 1-based CSV record number, so the header is 1.
  # Validation per row: title present (<= 500 chars), gamedb_id / igdb_id
  # positive integers and not both, ownership one of
  # CollectionApplier::OWNERSHIP_TYPES (blank = Digital), note <= 500 chars,
  # and a given platform must resolve via PlatformResolver#resolve.
  class CollectionCsvParser
    Row = Data.define(:row_index, :title, :raw_platform, :platform_id, :raw_ownership_type, :ownership_type,
      :raw_note, :gamedb_id, :igdb_id)

    Result = Data.define(:rows, :errors) do
      def ok? = errors.empty?
    end

    HEADER_ALIASES = {
      "title" => "title", "game" => "title", "game_title" => "title", "game_title_name" => "title",
      "game_name" => "title",
      "platform" => "platform", "platform_name" => "platform", "platform_id" => "platform",
      "ownership" => "ownership_type", "ownership_type" => "ownership_type", "ownershiptype" => "ownership_type",
      "note" => "note", "notes" => "note",
      "gamedb_id" => "gamedb_id", "gamedb" => "gamedb_id",
      "igdb_id" => "igdb_id", "igdb" => "igdb_id"
    }.freeze

    REQUIRED_HEADERS = %w[title].freeze
    MAX_TEXT_LENGTH = 500
    EXAMPLE_ROW_MARKER = "EXAMPLE ROW"

    def initialize(platform_resolver:)
      @platform_resolver = platform_resolver
    end

    def parse(csv_text)
      records = CSV.parse(csv_text.to_s.delete_prefix("﻿"), liberal_parsing: true)
      return failure(file_error("CSV file is empty.")) if records.empty?

      header, *data = records
      headers = header_map(header)
      missing = REQUIRED_HEADERS.reject { |column| headers.key?(column) }
      return failure(missing.map { |column| error(1, column, %(Missing required column "#{column}".)) }) if missing.any?

      rows = []
      errors = []
      data.each.with_index(2) do |values, row_index|
        row_errors = []
        row = parse_row(values, headers, row_index, row_errors)
        next if row.nil?

        row_errors.any? ? errors.concat(row_errors) : rows << row
      end

      return failure(errors) if errors.any?
      return failure(file_error("CSV file contains no importable rows.")) if rows.empty?

      Result.new(rows: rows, errors: [])
    rescue CSV::MalformedCSVError => malformed
      line = malformed.message[/line (\d+)/, 1]&.to_i || 1
      message = malformed.message.match?(/unclosed quoted field/i) ? "Unterminated quoted field." : "Malformed CSV."
      failure([ error(line, "file", message) ])
    end

    private

    # nil for a row to skip (blank or example), otherwise the Row; problems
    # are appended to `errors`.
    def parse_row(values, headers, row_index, errors)
      return if values.all? { |value| sanitize(value).empty? }

      cell = ->(column) { headers.key?(column) ? sanitize(values[headers[column]]) : "" }
      title = cell.call("title")
      raw_platform = cell.call("platform")
      raw_ownership = cell.call("ownership_type")
      raw_note = cell.call("note")
      return if raw_note.upcase.include?(EXAMPLE_ROW_MARKER)

      if title.empty?
        errors << error(row_index, "title", "Title is required.")
      elsif title.length > MAX_TEXT_LENGTH
        errors << error(row_index, "title", "Title must be #{MAX_TEXT_LENGTH} characters or fewer.")
      end

      gamedb_id = positive_id(cell.call("gamedb_id"), row_index, "gamedb_id", "GameDB", errors)
      igdb_id = positive_id(cell.call("igdb_id"), row_index, "igdb_id", "IGDB", errors)
      errors << error(row_index, "gamedb_id", "Provide only one of gamedb_id or igdb_id.") if gamedb_id && igdb_id

      ownership_type = CollectionApplier.normalize_ownership(raw_ownership)
      unless ownership_type
        errors << error(row_index, "ownership_type", "Ownership type must be Digital, Physical, Subscription, or Other.")
      end

      if raw_note.length > MAX_TEXT_LENGTH
        errors << error(row_index, "note", "Note must be #{MAX_TEXT_LENGTH} characters or fewer.")
      end

      platform_id = raw_platform.empty? ? nil : @platform_resolver.resolve(raw_platform)
      if raw_platform.present? && platform_id.nil?
        errors << error(row_index, "platform", "Platform not recognized. Use a platform name or id.")
      end

      Row.new(
        row_index: row_index, title: title, raw_platform: raw_platform.presence, platform_id: platform_id,
        raw_ownership_type: raw_ownership.presence, ownership_type: ownership_type,
        raw_note: raw_note.presence, gamedb_id: gamedb_id, igdb_id: igdb_id
      )
    end

    def header_map(header)
      header.each_with_index.with_object({}) do |(value, index), map|
        key = HEADER_ALIASES[normalize_header(value)]
        map[key] = index if key && !map.key?(key)
      end
    end

    def normalize_header(value)
      value.to_s.delete("﻿").strip.downcase.gsub(/[\s-]+/, "_").gsub(/[^\w]/, "")
    end

    def positive_id(raw, row_index, column, label, errors)
      return if raw.empty?

      id = Integer(raw, 10, exception: false)
      return id if id&.positive?

      errors << error(row_index, column, "#{label} id must be a positive number.")
      nil
    end

    # Trimmed, with control characters (newlines included) turned into spaces
    # (the bot's sanitizeUserInput without preserveNewlines).
    def sanitize(value)
      value.to_s.unicode_normalize(:nfkc).gsub(/[\p{Cc}​-‏‪-‮⁠-⁯﻿]+/, " ").squeeze(" ").strip
    end

    def error(row_index, column, message)
      { row_index: row_index, column: column, message: message }
    end

    def file_error(message)
      [ error(1, "file", message) ]
    end

    def failure(errors)
      Result.new(rows: [], errors: errors)
    end
  end
end
