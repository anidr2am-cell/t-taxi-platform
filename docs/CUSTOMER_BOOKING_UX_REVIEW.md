# Customer booking UX review

Base: `dd298dac4dc75371cdd1fa7aa1aff0d4bbc6af0f` (both origin/main and production at investigation).
PR: https://github.com/anidr2am-cell/t-taxi-platform/pull/237
Production deployment requires separate approval.

## Scope

1. Search before recent places; two recents initially, expandable. Passengers/luggage before vehicle cards, collapsible options and fare breakdown. Login benefits are deferred to completion; header login and booking lookup remain.
2. Static landing replaces the decorative journey panel with service/route entry. Route coordinates stay in a four-hour session draft, scoped by a non-authorizing entry ID. The existing booking API remains authoritative. Language changes retain landing entries; the customer language selector updates the URL without replacing Flutter history state, so reload retains the chosen language. Deliberate booking links start a new draft; reload/back retain the current one. Completion prioritizes the actual returned status, messenger handoff and lookup, with airport guidance before cancellation and optional benefits.
3. Traditional Chinese `zh-TW` is distinct from `zh`; script-aware Material date pickers, Taiwan phone default, customer copy and Traditional Chinese blog links. Japanese/Taiwan support prioritizes configured official LINE. Golf consultation distinguishes vehicle reservations from tee-time confirmation and does not add a two-player transport restriction.

No price, region, capacity, payment, assignment, cancellation or message-sending policy changes. Backend changes accept/store the added locale only. No SQL migration. No font/fallback, engine, renderer or Flutter index.html changes.

## Reused contracts

- Existing five-step controller, safe restored step, four-hour draft envelope and quote invalidation.
- Existing place search/details, airport catalog, flight lookup and Thailand-time conversion; unknown flights still permit manual entry.
- Existing capacity recommendation and per-vehicle pricing endpoints, including mixed-luggage constraints.
- Existing edit-and-return review navigation, request idempotency and API validation.
- Existing lookup/voucher authorization, airport instructions, customer status guidance and server contact states.
- Central public messenger configuration. No new messaging integration or sender.
- Existing analytics consent, attribution allowlist, event sanitization and completion deduplication. New UI events contain language/service/channel only; no route addresses, contact fields or access tokens.

## Storage and privacy

- Existing booking input uses `booking_wizard_draft_v2` with a four-hour envelope; derived quotes are recomputed. Existing authenticated-user recent-place partitioning remains.
- New landing-only keys: `tride_landing_form_v1` and `tride_landing_route_v1` in sessionStorage, checked against a four-hour expiry. They contain route entry only, no customer contact data or booking access token. A new intent gets a unique entry ID; refresh/back keep that ID.
- An `entry` parameter is a draft marker, never an authorization credential. Addresses are not put in the booking-entry URL or analytics.
- Existing authorized lookup cache/guest-token storage is retained. Client-side guest-token storage is not redesigned here; server authentication remains required. Directly revisiting `/booking` intentionally resumes the existing unexpired draft; new-booking buttons start clean.

## Preview and browser checks

See `frontend/qa/customer-booking-ux/README.md`. The preview is a real release web build against an isolated synthetic API with `X-Preview-Backend: customer-booking-ux-20261121-fixture`. No database, production network, SMTP or FCM is connected. Fixture fares illustrate UI and are not a new production tariff.

Browser scripts cover seven booking languages at 360/390/768/1280px, static-home wrapping and language/route handoff, plus synthetic completion, duplicate clicks and an accepted-but-lost response retry. External messenger navigation is intercepted; no message is sent. Real iPhone Safari and Android Chrome hardware remain unverified.

Windows golden differences were reproduced on the unchanged earlier source. Do not regenerate font-sensitive goldens for this change; use repository CI as the canonical platform check.

Verified reviews are not fabricated: no public approved-review feed was found, so the existing hidden review area remains unpublished. Current configured meeting instructions are reused; no unverified gate instruction is invented for DMK/UTP. Existing email/PDF language templates are outside this customer-web change.

## Deployment after approval

Follow `docs/PRODUCTION_DEPLOYMENT_RUNBOOK.md` and `docs/BACKUP_RESTORE_RUNBOOK.md`: verify only this PR is pending, record production HEAD/images, DB+uploads backup, SHA-256 and Drive readback. Rebuild backend then frontend with `--no-deps`; frontend-only deployment would reject the newly added booking locale on the old backend. No migration, DB restart, proxy restart, live reservation, payment or customer message is needed.

Rollback: restore the recorded previous backend/frontend images or previous source with the same `--no-deps` procedure. No SQL rollback or existing reservation/payment edits. A rollback restores the old language fallback for zh-TW links. Isolated preview processes can then be stopped independently of production.
