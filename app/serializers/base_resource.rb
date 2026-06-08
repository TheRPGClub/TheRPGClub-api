# frozen_string_literal: true

# Shared foundation for every Alba serializer in the app.
#
# Including this mixin pulls in `Alba::Resource` (the Alba serialization DSL)
# and adds the `columns_of` class macro.
#
#   class GamedbGameResource
#     include BaseResource
#     columns_of GamedbGame, except: %w[total_rating]
#   end
#
# Alba has no "dump every column" equivalent of ActiveRecord's `as_json`, so
# `columns_of` preserves the current all-columns contract without hand-listing
# every attribute.
module BaseResource
  extend ActiveSupport::Concern

  included do
    include Alba::Resource
  end

  class_methods do
    # Declare an attribute for every column on `model`, minus `except`.
    #
    # @param model [Class] an ActiveRecord model class
    # @param except [Array<String, Symbol>] column names to omit
    def columns_of(model, except: [])
      except = except.map(&:to_s)
      attributes(*(model.column_names - except))
    end
  end
end
