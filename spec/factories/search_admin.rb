# frozen_string_literal: true

# Factories for the search-admin / suggestion / wizard / game-key domain
# (behavior request specs). Unique-indexed columns use random values rather
# than plain sequences so concurrently running rspec processes can't collide
# inside their (uncommitted) transactions.
FactoryBot.define do
  factory :search_synonym_group, class: "GamedbSearchSynonymGroup" do
    created_by { SecureRandom.random_number(10**18).to_s }
  end

  factory :search_synonym, class: "GamedbSearchSynonym" do
    association :group, factory: :search_synonym_group
    term_text { "Term #{SecureRandom.hex(4)}" }
    term_norm { GamedbSearchSynonym.normalize_term(term_text) }
    created_by { SecureRandom.random_number(10**18).to_s }
  end

  factory :search_synonym_draft, class: "GamedbSearchSynonymDraft" do
    user_id { SecureRandom.random_number(10**18).to_s }
    pairs_json { '[{"from":"ff7","to":"final fantasy vii"}]' }
  end

  factory :suggestion, class: "RpgClubSuggestion" do
    title { "Suggestion #{SecureRandom.hex(4)}" }
    details { "Some details" }
    created_by { SecureRandom.random_number(10**18).to_s }
    created_by_name { "suggester_#{SecureRandom.hex(3)}" }
  end

  factory :suggestion_review_session, class: "RpgClubSuggestionReviewSession" do
    session_id { "sess-#{SecureRandom.hex(10)}" }
    reviewer_id { SecureRandom.random_number(10**18).to_s }
    suggestion_ids { "[1,2,3]" }
    current_index { 0 }
    total_count { 3 }
  end

  # Wizard sessions are seeded the way production rows actually exist: the DB
  # check constraint (ck_rpg_club_admin_wiz_sess_status) only accepts the
  # uppercase ACTIVE/COMPLETED/CANCELLED the Discord bot writes, while the
  # Rails model validates the lowercase active/completed/cancelled — so the
  # factory bypasses model validations to insert bot-shaped rows. (The model's
  # session_id before_validation hook is skipped too, hence the explicit id.)
  factory :wizard_session, class: "RpgClubAdminWizardSession" do
    session_id { SecureRandom.hex(16) }
    command_key { "nextround-setup" }
    owner_user_id { SecureRandom.random_number(10**18).to_s }
    channel_id { SecureRandom.random_number(10**18).to_s }
    guild_id { SecureRandom.random_number(10**18).to_s }
    status { "ACTIVE" }
    state_json { '{"step":1}' }
    last_updated_at { Time.current }

    to_create { |instance| instance.save!(validate: false) }

    trait :completed do
      status { "COMPLETED" }
    end

    trait :cancelled do
      status { "CANCELLED" }
    end
  end

  factory :game_key, class: "RpgClubGameKey" do
    game_title { "Key Game #{SecureRandom.hex(4)}" }
    platform { "Steam" }
    key_value { "KEY-#{SecureRandom.hex(8).upcase}" }
    donor_user_id { SecureRandom.random_number(10**18).to_s }
  end
end
