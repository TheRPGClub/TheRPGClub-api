# frozen_string_literal: true

# A Game News Archive message staff removed from the News Import with `skip`
# (spec #355, ticket #359). Its News Item is deleted; this record keeps a
# re-scan from recording the message again (NewsImport::RecordBatch).
class NewsImportRemoval < ApplicationRecord
  validates :message_id, presence: true, uniqueness: true
end
