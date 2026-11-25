# frozen_string_literal: true

# A UserGameCompletion with its embedded game and platform. `platform` renders
# `null` when the entry has no platform. The consumer-audited column set lives
# in CompletionFields (#36).
class CompletionEntryResource
  include BaseResource
  include ShelfPlaytimeFields.with
  include CompletionFields

  one :game, resource: GameSummaryResource
  one :platform, resource: PlatformResource
end
