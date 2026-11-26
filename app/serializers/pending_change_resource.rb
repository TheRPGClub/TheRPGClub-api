# frozen_string_literal: true

# A Pending Change as the API serves it (spec api#510, ticket api#514).
#
#   type          the pull request title's type (change_type)
#   section       the Patch section it drafts into: new, improved or fixed
#   status        open, covered or dismissed
#   patch_number  the Patch that covers it, if any
class PendingChangeResource
  include BaseResource

  attributes :id, :repo, :pr_number
  attribute(:type, &:change_type)
  attributes :title, :version, :patch_note, :section, :status, :patch_number, :dismissed_at, :created_at,
    :updated_at
end
