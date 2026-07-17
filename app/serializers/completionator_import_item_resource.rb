# frozen_string_literal: true

# The full RpgClubCompletionatorImportItem record (#164): every column, so the
# bot can read back both the raw parsed Completionator fields and the
# resolved match / outcome in one call.
class CompletionatorImportItemResource
  include BaseResource
  columns_of RpgClubCompletionatorImportItem
end
