# frozen_string_literal: true

module PinnedPages
  # A member's Pinned Pages (Members::OrderedList): their saved list in order,
  # or the club default until they first save one (`pinned_pages_customised`
  # on the member). Pins they can't see right now (a Feature Off or hidden by
  # a Feature Preference, a staff role lost) are kept on save, and the limit
  # counts them.
  class List < Members::OrderedList
    # How many pins the member can see room for: LIMIT less the pins they
    # can't see right now, which a save keeps and the limit counts.
    def room = [ LIMIT - hidden.size, 0 ].max

    private

    def catalog = PinnedPages
    def model = MemberPinnedPage
    def key_column = :page_key
    def customised_column = :pinned_pages_customised
    def list_name = "pages"
    def key_name = "page"
    def chosen_word = "pinned"

    def refusal(sent, kept)
      return if sent.size + kept.size <= LIMIT

      "at most #{LIMIT} Pinned Pages, counting #{kept.size} you can't see right now"
    end
  end
end
