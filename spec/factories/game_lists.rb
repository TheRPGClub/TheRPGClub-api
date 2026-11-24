# frozen_string_literal: true

# Game List factories (spec api#442). A :game_list is a member's
# Members-visible, ranked list; pass `owner: nil` for a club list.
FactoryBot.define do
  factory :game_list do
    owner factory: %i[user]
    sequence(:name) { |n| "Game List #{n}" }
    visibility { "members" }
    sort { "ranked" }
  end

  factory :game_list_entry do
    game_list
    game
    sequence(:position) { |n| n }
    added_at { Time.current }
  end
end
