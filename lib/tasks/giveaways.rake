# frozen_string_literal: true

namespace :giveaways do
  desc "Link unlinked giveaway keys to GameDB games by unique title match (Giveaways::LinkUnlinkedKeys). " \
       "DRY_RUN=1 reports without writing."
  task link_keys: :environment do
    # Any value but a false one (0, false, off...) is a dry run, so a typo
    # previews rather than writes.
    dry_run = ActiveModel::Type::Boolean.new.cast(ENV["DRY_RUN"].presence) || false
    report = Giveaways::LinkUnlinkedKeys.call(dry_run:)

    puts "#{dry_run ? 'Would link' : 'Linked'} #{report.linked} key(s); " \
         "#{report.ambiguous.values.sum} ambiguous, #{report.unmatched.values.sum} unmatched."
    { "Ambiguous" => report.ambiguous, "Unmatched" => report.unmatched }.each do |label, titles|
      next if titles.empty?

      puts "#{label} titles:"
      titles.each { |title, count| puts "  #{title} (#{count})" }
    end
  end
end
