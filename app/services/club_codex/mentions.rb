# frozen_string_literal: true

module ClubCodex
  # The members a Club Codex entry mentions (spec #397, "Mentions").
  #
  # In stored text a mention is a Discord mention token, `<@discord_id>` (the
  # older `<@!discord_id>` form too). On every save the tokens are pulled out
  # of the entry's `body` into codex_entry_mentions, the same way for every
  # part, so the API never parses Plate. A token for an id that is not a
  # known member stays in the text as it is and is not recorded.
  #
  # Payloads carry each mentioned member as they are now (ClubCodex.member),
  # keyed by Discord id, so clients show tokens as current names, never ids.
  module Mentions
    TOKEN = /<@!?(\d+)>/

    module_function

    # Replaces the entry's mentions with the known members its body names.
    def pull!(entry)
      ids = entry.body.to_s.scan(TOKEN).flatten.uniq
      known = ids.empty? ? [] : RpgClubUser.where(user_id: ids).pluck(:user_id)
      CodexEntryMention.where(entry_id: entry.id).where.not(user_id: known).delete_all
      return if known.empty?

      CodexEntryMention.insert_all(known.map { |user_id| { entry_id: entry.id, user_id: user_id } })
    end

    # Each entry's mentioned members, keyed by entry id, then Discord id, in
    # one query for a page of entries.
    def of(entries)
      by_entry = Hash.new { |hash, key| hash[key] = {} }
      CodexEntryMention.where(entry_id: entries.map(&:id)).preload(:user).each do |mention|
        by_entry[mention.entry_id][mention.user_id] = ClubCodex.member(mention.user)
      end
      by_entry
    end
  end
end
