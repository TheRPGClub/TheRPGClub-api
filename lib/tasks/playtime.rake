# frozen_string_literal: true

namespace :playtime do
  desc "Launch seed: turn Game Completions' final playtimes into Manual Playtime (safe to run again)"
  task seed_from_completions: :environment do
    result = Playtime::CompletionSeed.call
    puts "Seeded Manual Playtime from Game Completions: #{result.created} created, #{result.raised} raised, " \
         "#{result.skipped} skipped (a Provider reports Playtime)."
  end
end
