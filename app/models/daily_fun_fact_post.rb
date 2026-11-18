# frozen_string_literal: true

# A club day's Daily Fun Fact (GLOSSARY.md, "Daily Fun Fact"; ticket #406):
# one per club date (ux_daily_fun_fact_posts_club_date), so the post is
# queued once however often the job runs. Written only by
# ClubCodex::DailyFunFactJob, when it queues the post. The entry goes null
# when the Fun Fact is deleted; the day stays posted.
class DailyFunFactPost < ApplicationRecord
  belongs_to :entry, class_name: "CodexEntry", optional: true, inverse_of: false
end
