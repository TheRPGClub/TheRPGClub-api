# frozen_string_literal: true

# A queued Discord post for the bot (see VotingEvent), for a GOTM round
# (`round_number`) or a GOTY Vote (`goty_year`). A round's `payload` carries
# the ids the post needs (winners / ties per category, the relevant
# deadline); a GOTY Vote's is self-contained (Goty::EventPayload).
class VotingEventResource
  include BaseResource

  attributes :id, :round_number, :goty_year, :kind, :payload, :available_at, :expires_at, :claimed_until,
             :delivered_at, :attempts
end
