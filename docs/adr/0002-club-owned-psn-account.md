# PSN is read through one club-owned account

Sony has no public API for third-party trophy access, so all PSN reads go through a single dedicated, club-owned PSN account whose NPSSO token is stored in credentials; members' trophies are fetched via the `users/{accountId}` endpoints and therefore only work when the member's trophy privacy is public. We rejected per-member NPSSO tokens (members would be handing us their Sony session) and using the club owner's personal account (a ban or expiry would hit their real profile).

## Consequences

- The NPSSO expires roughly every two months; PSN syncs pause and the bot alerts admins until it is refreshed.
- A PSN Linked Account stores the resolved accountId, not just the online ID.
