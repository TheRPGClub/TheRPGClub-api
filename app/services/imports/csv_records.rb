# frozen_string_literal: true

require "csv"

module Imports
  # Reads CSV text into records tagged with the 1-based physical line each
  # one starts on, for the import parsers' `row_index`. Ruby's CSV#lineno
  # counts records, so a quoted multiline field would shift every later row;
  # this counts the line breaks inside the fields instead.
  #
  #   Imports::CsvRecords.parse("title\n\"a\nb\"\nc\n")
  #   # => [Record(fields: ["title"], line: 1), Record(fields: ["a\nb"], line: 2),
  #   #     Record(fields: ["c"], line: 4)]
  #
  # A leading BOM is dropped. Blank lines are kept as empty records (they
  # still take up a line). Malformed CSV raises Malformed, whose `line` is
  # where the broken record starts.
  module CsvRecords
    Record = Data.define(:fields, :line)

    class Malformed < StandardError
      attr_reader :line

      def initialize(message, line)
        super(message)
        @line = line
      end
    end

    module_function

    def parse(text, **options)
      csv = CSV.new(text.to_s.delete_prefix("﻿"), **options)
      line = 1
      records = []
      while (fields = shift(csv, line))
        records << Record.new(fields: fields, line: line)
        line += 1 + fields.sum { |field| field.to_s.count("\n") }
      end
      records
    end

    def shift(csv, line)
      csv.shift
    rescue CSV::MalformedCSVError => error
      raise Malformed.new(error.message, line)
    end
    private_class_method :shift
  end
end
