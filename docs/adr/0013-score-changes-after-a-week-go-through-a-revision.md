# A Review's score changes after its first week only through a Revision

An Edit to a Published Review or Revision may change its score only in the first 7 days after it was published; after that the score is locked, and a member who has changed their mind publishes a Revision, which keeps the earlier take and score readable beneath it. Text stays editable forever, and an Edit made more than an hour after publishing marks the take as edited. We rejected free score edits, because a silent change of score is a change of opinion that readers, the Review Feed and any per-game averages could never see; and we rejected locking the score at publish, because mis-clicks and first-day second thoughts are corrections, not revisits. Text edits are left unpoliced because no rule can tell a reworded sentence from a reversed opinion; the score is the one part where a change is unambiguous.

## Consequences

- The API refuses an Edit that changes the score of a take published more than 7 days ago, and the website shows the score as locked with a way to Revisit instead.
- The 7 days run separately for each take: a Revision's score has its own window from its own publish date.
- No edit history is kept; the "edited" marker is the only trace of an Edit.
