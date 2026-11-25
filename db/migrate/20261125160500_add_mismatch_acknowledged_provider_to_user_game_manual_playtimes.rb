# frozen_string_literal: true

# "Keep both" on a Playtime mismatch (spec api#457, fix pass; ADR 0015):
# the Provider whose figure on this entry's platform the member chose to count
# alongside their Manual entry. Both still count; the pair just stops being
# reported as a mismatch. Moving the entry to another platform clears it.
class AddMismatchAcknowledgedProviderToUserGameManualPlaytimes < ActiveRecord::Migration[8.1]
  def change
    add_column :user_game_manual_playtimes, :mismatch_acknowledged_provider, :string, limit: 32
  end
end
