# frozen_string_literal: true

# The public face of a Linked Account on hub reads: the Provider and the
# member's display name there. Ids and sync state stay private.
class LinkedAccountSummaryResource
  include BaseResource

  attributes :provider, :display_name
end
