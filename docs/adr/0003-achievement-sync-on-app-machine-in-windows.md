# Achievement sync runs on the app machine, in Sync Windows

Sync jobs run in the existing in-Puma Solid Queue on the single Fly app machine, on a one-thread `bulk` queue with global per-Provider pacing, and are scheduled as four daily Sync Windows (00/06/12/18 UTC) rather than staggered per account. The queue database is machine-local SQLite so that queue polling never wakes Neon; a separate worker machine would have its own queue that the API couldn't enqueue into, and moving the queue to Neon would keep it awake around the clock. Batching syncs into windows lets Neon autosuspend between them, and the bot's highlights check rides its existing hourly tick for the same reason.

## Considered Options

- **Separate Fly worker machine** with its own SQLite queue, fed by the API over private networking. Revisit if `[JobCPU]` logs show sync starving API requests.
- **Staggered per-account schedule.** Rejected: spreads database wake-ups across the whole day.
