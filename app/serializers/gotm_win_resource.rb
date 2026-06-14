# frozen_string_literal: true

# A single GOTM / NR-GOTM win for the aggregate game profile's `associations`
# block (#115): just the round number the game won. Both GotmEntry and
# NrGotmEntry expose `round_number`, so this one resource serves the
# `gotm_wins` and `nr_gotm_wins` lists alike (a GotmEntry/NrGotmEntry row *is*
# a win — the winners table behind each round).
class GotmWinResource
  include BaseResource

  attribute(:round) { |entry| entry.round_number }
end
