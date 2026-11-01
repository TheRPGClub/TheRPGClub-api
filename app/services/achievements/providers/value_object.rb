# frozen_string_literal: true

module Achievements
  module Providers
    # Data.define with every member optional (nil by default), so each
    # Provider fills only the fields it has.
    module ValueObject
      def self.define(*members)
        Data.define(*members) do
          def initialize(**attrs)
            super(**self.class.members.index_with(nil).merge(attrs))
          end
        end
      end
    end
  end
end
