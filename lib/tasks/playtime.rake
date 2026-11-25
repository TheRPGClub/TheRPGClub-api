# frozen_string_literal: true

namespace :playtime do
  desc "Launch seed: turn Game Completions' final playtimes into Manual Playtime. Only creates entries, never adds " \
       "onto one, and leaves out Completions a Playthrough closed, so running it again changes nothing"
  task seed_from_completions: :environment do
    result = Playtime::CompletionSeed.call
    puts "Seeded Manual Playtime from Game Completions: #{result.created} created, " \
         "#{result.kept} kept (an entry was already there), #{result.skipped} skipped (a Provider reports Playtime)."
  end
end
