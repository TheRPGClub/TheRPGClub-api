# frozen_string_literal: true

# A Pool game with who Cleared it and who has it In Progress
# (Challenges::PoolProgress), for GET /api/v1/challenges/{id}/pool_progress.
# `params[:progress]` is Challenges::PoolProgress.of the page's games.
class ChallengePoolGameProgressResource
  include BaseResource

  attributes :game_id, :title, :initial_release_date, :cover_url

  attribute(:cleared_by) { |game| params[:progress].fetch(game.game_id)[:cleared_by] }
  attribute(:in_progress) { |game| params[:progress].fetch(game.game_id)[:in_progress] }
end
