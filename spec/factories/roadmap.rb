# frozen_string_literal: true

# Roadmap factories (spec api#505). A :roadmap_milestone is open and TBA; a
# :roadmap_item is not Shipped and touches no particular area.
FactoryBot.define do
  factory :roadmap_milestone do
    sequence(:name) { |n| "Milestone #{n}" }
    sequence(:position) { |n| n }
  end

  factory :roadmap_item do
    milestone factory: %i[roadmap_milestone]
    sequence(:title) { |n| "Roadmap Item #{n}" }
    blurb { "Something members will notice." }
    sequence(:position) { |n| n }
  end
end
