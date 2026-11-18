# frozen_string_literal: true

# Club Codex factories (spec #397). A :codex_entry is a Fun Fact by default.
FactoryBot.define do
  factory :codex_entry do
    author factory: %i[user]
    part { "fun_fact" }
    sequence(:body) { |n| "Fun Fact #{n}: the club once voted for a game nobody had played." }

    trait :fun_fact do
      part { "fun_fact" }
    end

    trait :history_event do
      part { "history_event" }
      sequence(:title) { |n| "History Event #{n}" }
      body { nil }
      occurred_on { Date.new(2018, 3, 1) }
      date_precision { "month" }
      kind { "milestone" }
    end
  end
end
