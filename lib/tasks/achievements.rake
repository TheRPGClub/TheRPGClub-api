# frozen_string_literal: true

namespace :achievements do
  desc "Relink unlinked Achievement Sets to GameDB games (Achievements::LinkSetToGame)"
  task link_sets: :environment do
    linked = Achievements::LinkSetToGame.link_unlinked
    puts "Linked #{linked} Achievement Set(s); #{AchievementSet.where(game_id: nil).count} still unlinked."
  end
end
