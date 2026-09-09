# frozen_string_literal: true

# Two Rails-side incompatibilities with json 3, both already fixed on
# rails/rails main. This whole file can be deleted once a Rails release
# carrying them ships. See #244; #242 carries the original investigation.
#
# json 3.0 narrowed JSON.parse from `parse(source, opts = nil)` to
# `parse(source, on_load: nil, object_class: nil, array_class: nil, **options)`
# and hands the leftover keywords straight to the C parser, which now rejects
# any it does not recognise.

require "active_support/json/decoding"

# (1) ActiveSupport 8.1.3.1 still forwards its options hash positionally
# (active_support/json/decoding.rb:25). Ruby 3 does not convert a trailing
# positional Hash into keywords, so under json >= 3 every
# ActiveSupport::JSON.decode call raises
#
#   ArgumentError: wrong number of arguments (given 2, expected 1)
#
# including the serialize/deserialize round-trip that
# ActiveModel::Type::Helpers::Mutable performs on assignment to any jsonb
# attribute.
#
# Splatting is correct on both json majors: json 2's `parse` declares no
# keywords, so Ruby folds them back into the positional Hash it expects.
module JsonKeywordOptions
  def decode(json, options = {})
    data = ::JSON.parse(json, **options)

    if ActiveSupport.parse_json_times
      convert_dates_from(data)
    else
      data
    end
  end
end

ActiveSupport::JSON.singleton_class.prepend(JsonKeywordOptions)

# (2) ActiveRecord::Coders::JSON conflates encode and decode options: it builds
# one hash defaulting to `{ escape: false }` -- an *encoder* setting -- and
# passes it to both the encoder and ActiveSupport::JSON.decode. json 2 ignored
# the stray key; with (1) in place json 3 sees it as a keyword and raises
#
#   ArgumentError: unknown keyword: escape
#
# on every read of a `serialize coder: JSON` attribute, SolidQueue::Process
# metadata included. Upstream splits the two sets of options; mirrored below.
# The kwargs signature matches upstream, and Coders::JSON.new is only ever
# called without arguments (active_record/attribute_methods/serialization.rb).
module JsonCoderOptions
  DEFAULT_ENCODE_OPTIONS = { escape: false }.freeze

  def initialize(encode_options: nil, decode_options: nil)
    encode_options = encode_options ? DEFAULT_ENCODE_OPTIONS.merge(encode_options) : DEFAULT_ENCODE_OPTIONS
    @decode_options = decode_options
    @encoder = ActiveSupport::JSON::Encoding.json_encoder.new(encode_options)
  end

  def load(json)
    ActiveSupport::JSON.decode(json, @decode_options) unless json.blank?
  end
end

ActiveSupport.on_load(:active_record) do
  ActiveRecord::Coders::JSON.prepend(JsonCoderOptions)
end
