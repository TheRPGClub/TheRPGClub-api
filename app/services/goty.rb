# frozen_string_literal: true

# The yearly GOTY Vote (spec api#471; GLOSSARY "GOTY Vote"): three Awards,
# each voted on like a GOTM round.
module Goty
  # The Awards in the order members see them. GOTM and NR-GOTM of the Year
  # take their ballots from the year's round winners (Goty::Ballots); Game of
  # the Year takes its from member nominations.
  AWARDS = {
    "gotm" => "GOTM of the Year",
    "nr_gotm" => "NR-GOTM of the Year",
    "game_of_the_year" => "Game of the Year"
  }.freeze

  def self.award_name(award)
    AWARDS.fetch(award.to_s)
  end
end
