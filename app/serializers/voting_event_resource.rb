# frozen_string_literal: true

# A queued Discord post for the bot (see VotingEvent). `payload` carries the
# ids the post needs (winners / ties per category, the relevant deadline);
# the bot reads everything else from the regular endpoints.
class VotingEventResource
  include BaseResource

  attributes :id, :round_number, :kind, :payload, :available_at, :expires_at, :claimed_until,
             :delivered_at, :attempts
end
