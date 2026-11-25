# frozen_string_literal: true

# A member's Conquest of a Franchise (GLOSSARY.md "Conquered"; spec api#457,
# ticket api#461): written once by Franchises::ConquestCheck when they hold a
# Game Completion for every Mainline game, and kept from then on, whatever
# later Mainline additions or deleted Completions do. `completion_id` is the
# Completion that finished the set (null once that Completion is deleted);
# `announce` is false for Conquests that were never posted (the launch
# backfill and Completionator imports).
class UserFranchiseConquest < ApplicationRecord
  belongs_to :user, class_name: "RpgClubUser", foreign_key: :user_id, primary_key: :user_id, inverse_of: false
  belongs_to :franchise, class_name: "GamedbFranchise", foreign_key: :franchise_id, inverse_of: false
  belongs_to :completion, class_name: "UserGameCompletion", foreign_key: :completion_id, optional: true,
    inverse_of: false
end
