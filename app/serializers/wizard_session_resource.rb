# frozen_string_literal: true

# Serializes a RpgClubAdminWizardSession (all columns). `state_json` is
# rendered verbatim as the stored JSON string; the bot parses it client-side.
class WizardSessionResource
  include BaseResource

  columns_of RpgClubAdminWizardSession
end
