# frozen_string_literal: true

# One row of the thread search (GET /threads?q=) behind the thread link
# picker: the thread's id and name plus the games it is linked to, each as
# `{ game_id, title }`. Expects `games` preloaded.
class ThreadSearchResultResource
  include BaseResource

  attributes :thread_id, :thread_name

  attribute :games do |thread|
    thread.games.sort_by(&:title).map { |game| { game_id: game.game_id, title: game.title } }
  end
end
