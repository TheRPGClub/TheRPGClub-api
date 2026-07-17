# frozen_string_literal: true

# Shared write-rollback helper for the Steam collection import test mode
# (#166). A SteamCollectionImport created with `test_mode: true` lets the bot
# run a full import without leaving any trace: the session row itself is
# always persisted (so it has a stable import_id to reference across
# requests), but every subsequent write scoped to it — bulk item insert,
# item updates, status/current_index updates — runs inside a transaction that
# is rolled back before the response is sent. The response still reflects the
# write as if it had succeeded; nothing survives to the next request.
module TestModeRollback
  extend ActiveSupport::Concern

  private

  def with_test_mode_rollback(test_mode)
    result = nil
    ActiveRecord::Base.transaction do
      result = yield
      raise ActiveRecord::Rollback if test_mode
    end
    result
  end
end
