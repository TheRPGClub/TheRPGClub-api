# A Member's Theme is stored on the Member and gated by one Themes Feature

Members choose the website's Theme (ADR 0008). The choice is a nullable `theme` column on the Member's own user row, where empty means "follow the club's default Theme". It is returned in the session payload the website already reads on every signed-in page, so it follows the Member to every device and browser with no cookie copy. Who may pick a Theme other than the default is decided by the API (ADR 0005), through a single Core Feature, **Themes**, plus a released marker on each Theme in the API's list of Themes, which is kept in code. Themes being Off, Preview or Live decides who sees the picker. A Theme that is not yet released can be picked only by staff, even while Themes is Live. We rejected three alternatives. A cookie as the store would lose the choice on a new device or after signing out. One Feature per Theme would grow the Feature list with every Theme, even though Members can't hide a Theme and staff never switch one off on its own. A non-null column defaulting to the current default Theme would need a data migration that guesses who really chose it whenever the club changes its default.

## Consequences

- Adding a Theme needs an API release, to add its key to the list unreleased, as well as the website release that ships its stylesheet. Releasing it is a one-line API change. The website's `themes/registry.ts` is tested against the API's keys.
- When a Member's Theme is unavailable to them (Themes Off, Themes in Preview for a non-staff Member, an unreleased Theme for a non-staff Member, or a key the API no longer knows), the session reports the default Theme. The stored choice is kept, so it comes back when the Theme does.
- Signed-out pages (the landing page, `/join`, public Club History) always render the default Theme, as do the Share Card images. They are the club's public face.
- The browser `theme-color` follows the Member's Theme on signed-in pages.
