# frozen_string_literal: true

# The website's Share Card (GLOSSARY.md, "Share Card"): the link preview,
# which shows the latest decided GOTM round's winners. The API tells the
# website to refresh it when a round is decided (ShareCard::RefreshJob).
module ShareCard
  module_function

  # Queues the refresh once the current transaction commits (at once outside
  # one), so the website never reads the winners before they are saved and a
  # rolled-back decision queues nothing. GOTM rounds only: a GOTY Vote is not
  # on the card.
  def refresh_later
    ActiveRecord.after_all_transactions_commit { RefreshJob.perform_later }
  end
end
