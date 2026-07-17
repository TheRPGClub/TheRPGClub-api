# frozen_string_literal: true

# The full RpgClubCompletionatorImport record (#164): every column, matching
# the documented "full record" contract used by the other job-style resources
# (e.g. WizardSessionResource).
class CompletionatorImportResource
  include BaseResource
  columns_of RpgClubCompletionatorImport
end
