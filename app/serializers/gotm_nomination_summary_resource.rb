# frozen_string_literal: true

# A trimmed GOTM / NR-GOTM nomination for the aggregate game profile's
# `associations` block (#115): the round the game was nominated for plus the
# nominating member (`user_id` + `username`). Both GotmNomination and
# NrGotmNomination share this shape, so one resource serves the
# `gotm_nominations` and `nr_gotm_nominations` lists.
#
# This is intentionally lighter than NominationResource (which embeds the full
# user/game summaries and the `reason`/`nominated_at` fields for the standalone
# nominations endpoints). The `user` association is bot-sourced and unenforced
# by a FK, so `username` is null when it doesn't resolve.
class GotmNominationSummaryResource
  include BaseResource

  attribute(:round) { |nomination| nomination.round_number }
  attributes :user_id
  attribute(:username) { |nomination| nomination.user&.username }
end
