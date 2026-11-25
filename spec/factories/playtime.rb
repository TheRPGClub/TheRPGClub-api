# frozen_string_literal: true

# Playtime factories (spec api#457).
FactoryBot.define do
  factory :manual_playtime, class: "UserGameManualPlaytime" do
    user
    game
    minutes { 60 }
  end
end
