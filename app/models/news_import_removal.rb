# frozen_string_literal: true

# An imported News Item staff removed from the News Import with `skip`
# (spec #355, ticket #359). Its News Item is deleted; this record keeps the
# removal counted (`removed` in the News Import status) and refuses a later
# News Category for it.
class NewsImportRemoval < ApplicationRecord
  validates :message_id, presence: true, uniqueness: true
end
