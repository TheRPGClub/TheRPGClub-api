# frozen_string_literal: true

# Factories for the import-job domain (#163/#164/#166): collection CSV,
# Completionator, and Steam collection import sessions with their per-row
# items, plus the shared Steam app -> GameDB mapping cache. The import models
# have no `belongs_to :user` (user_id is a bare Discord id column), so the
# owning user is a transient — pass `user: some_user` to tie a session to an
# authenticated principal. Unique-indexed columns use random values rather
# than plain sequences so concurrently running rspec processes can't collide
# (row_index only has to be unique per import, so a per-factory sequence is
# safe there).
FactoryBot.define do
  factory :collection_csv_import, class: "RpgClubCollectionCsvImport" do
    transient do
      user { create(:user) }
    end

    user_id { user.user_id }
    status { "active" }
    current_index { 0 }
    total_count { 0 }
    test_mode { false }
  end

  factory :collection_csv_import_item, class: "RpgClubCollectionCsvImportItem" do
    import factory: :collection_csv_import
    sequence(:row_index)
    status { "pending" }
    raw_title { "CSV Game #{SecureRandom.hex(4)}" }
  end

  factory :completionator_import, class: "RpgClubCompletionatorImport" do
    transient do
      user { create(:user) }
    end

    user_id { user.user_id }
    status { "active" }
    current_index { 0 }
    total_count { 0 }
    test_mode { false }
  end

  factory :completionator_import_item, class: "RpgClubCompletionatorImportItem" do
    import factory: :completionator_import
    sequence(:row_index)
    status { "pending" }
    game_title { "Completionator Game #{SecureRandom.hex(4)}" }
  end

  factory :steam_collection_import, class: "RpgClubSteamCollectionImport" do
    transient do
      user { create(:user) }
    end

    user_id { user.user_id }
    status { "active" }
    current_index { 0 }
    total_count { 0 }
    steam_id64 { "7656119#{SecureRandom.random_number(10**10)}" }
    test_mode { false }
  end

  factory :steam_collection_import_item, class: "RpgClubSteamCollectionImportItem" do
    import factory: :steam_collection_import
    sequence(:row_index)
    status { "pending" }
    steam_app_id { SecureRandom.random_number(1_000_000_000) }
    steam_app_name { "Steam App #{SecureRandom.hex(4)}" }
  end

  factory :steam_app_gamedb_map, class: "RpgClubSteamAppGamedbMap" do
    steam_app_id { SecureRandom.random_number(1_000_000_000) }
    status { "mapped" }
  end
end
