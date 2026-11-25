# Runbook: the club PSN login expired

The Achievement Hub reads every member's PSN trophies through the club-owned
PSN account (ADR 0002). It logs in with that account's NPSSO, a Sony session
cookie stored as the `PSN_NPSSO` secret. NPSSOs expire (roughly every two
months, sooner if the account signs out everywhere).

## How you find out

When a login fails, the API sets `psn_auth_expired_at` and pauses every PSN
sync. It also asks the bot to post `psn_auth_expired` in the staff channel,
and repeats it as a reminder at most once a day while the login stays expired.
When a login works again, the bot posts `psn_auth_restored` and PSN sync
picks up where it stopped.

## Fix it

1. **Get a fresh NPSSO.** In a browser, sign in to
   https://www.playstation.com as the club account. Then open
   https://ca.account.sony.com/api/v1/ssocookie in the same browser. It shows
   `{"npsso":"..."}`. Copy the value (64 characters). Treat it like a
   password: anyone holding it is logged in as the club account.

2. **Set it on Fly.**

   ```sh
   fly secrets set PSN_NPSSO=<the value>
   ```

   This restarts the app. On boot, the catch-up job
   (`Achievements::BootCatchUpJob`) sees the PSN pause and the NPSSO, tries
   one PSN login, and on success clears the flag (the bot posts
   `psn_auth_restored`) and restarts the PSN tick chain. Usually that is all.

Steps 3 and 4 are fallbacks for when the boot login did not clear the flag
(Sony was briefly down, or the Achievement Hub was Off during the boot). The
next Sync Window (00/06/12/18 UTC) also tries a login by itself.

3. **Log in once by hand** to clear the flag:

   ```sh
   fly ssh console -C "bin/rails runner 'Psn::Client.new.send(:access_token)'"
   ```

   It raises `AuthExpired` if Sony still refuses the NPSSO: go back to step 1.

4. **Restart the PSN chain:**

   ```sh
   fly ssh console -C "bin/rails runner 'Achievements::ProviderTickJob.perform_later(\"psn\")'"
   ```

## Check

- `AchievementHubState.get("psn_auth_expired_at")` is `nil`.
- The bot posted `psn_auth_restored` in the staff channel.
- PSN accounts' `last_synced_at` moves again after the next Sync Window.
