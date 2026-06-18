# frozen_string_literal: true

# A single GOTM / NR-GOTM win for the aggregate game profile's `associations`
# block (#115): the round number the game won plus the Reddit discussion thread
# link (#120). Both GotmEntry and NrGotmEntry expose `round_number` and a
# nullable `reddit_url`, so this one resource serves the `gotm_wins` and
# `nr_gotm_wins` lists alike (a GotmEntry/NrGotmEntry row *is* a win — the
# winners table behind each round). `reddit_url` is null when the round had no
# discussion thread recorded.
class GotmWinResource
  include BaseResource

  attribute(:round) { |entry| entry.round_number }
  attributes :reddit_url
end
