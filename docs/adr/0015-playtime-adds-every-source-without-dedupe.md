# Playtime adds every source together, with no dedupe

A member's Playtime for a game can come from several places: Steam, RetroAchievements and PSN each report their own figure, and the member can record Manual Playtime per platform for play no Provider sees (a Switch save file, an emulator, an old note, or PSN before we can sync it). We decided that Playtime is the plain sum of every source. We rejected letting a manual figure override the synced ones, because manual time is usually the only record of play on another platform, not a correction. We also rejected taking the largest figure, because play on different platforms really does add up. Automatic dedupe was rejected because we cannot tell a duplicate from a second playthrough on another platform.

## Consequences

- A member who types time that a Provider already reports counts it twice. Every Playtime is shown with a per-source breakdown so the mistake is visible and fixable.
- When a Provider starts reporting a platform that already has a Manual Playtime entry (for example once PSN Playtime lands), the member is told and chooses which to keep. Nothing changes automatically.
- At launch, a Game Completion's final playtime becomes a Manual Playtime entry only for games where no Provider reports Playtime, so seeding does not double count synced games.
