# The API owns the list of pages that can be pinned

The API defines which website pages a member can pin, each with the Feature or staff level it needs. It rejects pins for keys it doesn't know, and returns only the Pinned Pages the member can currently see, while keeping the hidden ones saved. We rejected letting the website own the list, with the API storing whatever keys it is sent, because then access to a pinned page would be decided by the website rather than by the API, against ADR 0005. It would also split "hidden while unavailable, kept for later" across two codebases.

## Consequences

- Making a new page pinnable needs an API release as well as a website one, in the same way that adding a Feature does.
- Pins whose key the API no longer knows, because the page was removed, are ignored when read and dropped the next time that member's list is saved.
