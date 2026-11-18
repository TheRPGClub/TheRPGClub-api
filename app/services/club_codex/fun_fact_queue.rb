# frozen_string_literal: true

module ClubCodex
  # The Fun Fact queue (GLOSSARY.md, "Fun Fact"; spec #397, ticket #405):
  # every Fun Fact is shown once before any is shown again, and a new Fun
  # Fact goes next. `/funfact` (POST /api/v1/codex/fun_facts/draw) and the
  # Daily Fun Fact both draw from it.
  #
  # The order needs no cycle state, only `last_shown_at`:
  #   1. never shown, newest first
  #   2. then shown longest ago
  #   ties break on the lowest id
  # Editing a Fun Fact leaves `last_shown_at` alone, so it keeps its place;
  # a deleted one is gone from the table, so it is never drawn.
  module FunFactQueue
    ORDER = Arel.sql(
      "last_shown_at ASC NULLS FIRST, CASE WHEN last_shown_at IS NULL THEN created_at END DESC, id ASC"
    )

    module_function

    # The Fun Facts in the order they will be drawn.
    def ordered = CodexEntry.fun_facts.order(ORDER)

    # Picks the next Fun Fact, marks it shown at `at` and returns it; nil
    # when there are none. Join a caller's transaction to draw only if the
    # rest of its work commits (the daily job records its post with it).
    #
    # The picked row is locked, and a concurrent draw skips it, so two
    # draws never get the same Fun Fact while another is free. Only when
    # every Fun Fact is being drawn at once does a draw wait for the queue's
    # head and repeat it, rather than say there are none.
    def draw!(at: Time.current)
      CodexEntry.transaction do
        entry = ordered.lock("FOR UPDATE SKIP LOCKED").first || ordered.lock.first
        # Not an edit: `updated_at` stays as the author left it.
        entry&.update_columns(last_shown_at: at) # rubocop:disable Rails/SkipsModelValidations
        entry
      end
    end
  end
end
