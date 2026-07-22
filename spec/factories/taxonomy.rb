# frozen_string_literal: true

# Factories for the taxonomy master tables plus the collection-entry and
# social-platform models exercised by their behavior request specs. As in
# core.rb, unique-indexed columns use random values rather than plain
# sequences so concurrently running rspec processes can't collide inside
# their (uncommitted) transactions.
FactoryBot.define do
  factory :company, class: "GamedbCompany" do
    sequence(:name) { |n| "Company #{n} #{SecureRandom.hex(4)}" }
    igdb_company_id { SecureRandom.random_number(1_000_000_000) }
  end

  factory :engine, class: "GamedbEngine" do
    sequence(:name) { |n| "Engine #{n} #{SecureRandom.hex(4)}" }
    igdb_engine_id { SecureRandom.random_number(1_000_000_000) }
  end

  factory :franchise, class: "GamedbFranchise" do
    sequence(:name) { |n| "Franchise #{n} #{SecureRandom.hex(4)}" }
    igdb_franchise_id { SecureRandom.random_number(1_000_000_000) }
  end

  factory :mode, class: "GamedbGameModeDef" do
    sequence(:name) { |n| "Mode #{n} #{SecureRandom.hex(4)}" }
    igdb_game_mode_id { SecureRandom.random_number(1_000_000_000) }
  end

  factory :perspective, class: "GamedbPerspective" do
    sequence(:name) { |n| "Perspective #{n} #{SecureRandom.hex(4)}" }
    igdb_perspective_id { SecureRandom.random_number(1_000_000_000) }
  end

  factory :theme, class: "GamedbTheme" do
    sequence(:name) { |n| "Theme #{n} #{SecureRandom.hex(4)}" }
    igdb_theme_id { SecureRandom.random_number(1_000_000_000) }
  end

  factory :region, class: "GamedbRegion" do
    # region_code is varchar(10) and unique: "R" + 8 hex chars fits.
    region_code { "R#{SecureRandom.hex(4)}" }
    sequence(:region_name) { |n| "Region #{n} #{SecureRandom.hex(4)}" }
  end

  factory :social_platform, class: "SocialPlatform" do
    # label is unique case-insensitively (functional index on lower(label)).
    label { "Social #{SecureRandom.hex(6)}" }
  end

  # A UserGameCollection row (the model behind collections#*), named after the
  # CollectionEntry shape it serializes to. ownership_type defaults to the
  # DB default; the platform association is optional and passed explicitly
  # where a spec needs the joined platform fields.
  factory :collection_entry, class: "UserGameCollection" do
    user
    game
    ownership_type { "Digital" }
  end
end
