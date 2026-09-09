# frozen_string_literal: true

# json 3.0 narrowed JSON.parse from `parse(source, opts = nil)` to
# `parse(source, on_load: nil, object_class: nil, array_class: nil, **options)`,
# but ActiveSupport 8.1.3.1 still forwards its options hash positionally
# (active_support/json/decoding.rb:25). Ruby 3 does not convert a trailing
# positional Hash into keywords, so under json >= 3 every
# ActiveSupport::JSON.decode call raises
#
#   ArgumentError: wrong number of arguments (given 2, expected 1)
#
# including the serialize/deserialize round-trip that
# ActiveModel::Type::Helpers::Mutable performs on assignment to any jsonb
# attribute. See #244; #242 carries the original investigation.
#
# The body below is Rails' own fix (rails/rails main already carries
# `::JSON.parse(json, **options)`), so this shim can be deleted wholesale once
# a release including it ships. Splatting is correct on both json majors:
# json 2's `parse` declares no keywords, so Ruby folds them back into the
# positional Hash it expects.
require "active_support/json/decoding"

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
