# Customer booking experience preview (2026-10-17)

Scope: customer vehicle comparison, registered airport shortcuts, fresh landing entries, authenticated booking vouchers and preferred support channels. Production deployment is not authorized. No fare, region, capacity-rule, migration, driver-app, font, renderer, engine or Flutter index changes.

## Implementation

- Existing pricing API is called for SEDAN/SUV/VAN with the same route, pickup time, passengers, luggage, golf package and options. Results are generation-guarded. Capacity-ineligible vehicles still display prices, but cannot be selected. Inquiry responses display inquiry on all cards.
- Recommendation returns active capacity rule combinations for display only. Recommendation rules and data are unchanged. Each rule is shown separately; independently taking column maxima would misrepresent capacity.
- `/api/v1/airports` exposes only active pricing regions with airport IATA codes. Booking shortcuts filter the existing coordinate catalog with this response; CNX/HKT no longer appear unless explicitly activated as pricing airport regions.
- A service query collapses service choices to the selected service plus Change. A landing service click adds a new random `entry` token. The first visit consumes that token in sessionStorage and clears the four-hour booking draft. Reload/back on the same entry does not clear it. A service URL without an entry is consumed once per tab/session and complete URL. Flutter landing service arguments explicitly request a fresh entry. Recent places are separate and are not deleted.
- Draft remains SharedPreferences `booking_wizard_draft_v2` (web: `flutter.booking_wizard_draft_v2`), version 3, four-hour TTL. Derived pricing/recommendation are not persisted.
- Vouchers reuse authenticated guest/member lookup results. No new unauthenticated booking access. Member phone visibility still waits for customer JWT. Driver portrait files are served through a booking-scoped, authenticated endpoint, not a public file URL.
- Airport meeting instructions: existing operations settings keys `meetingBKK_ko` through `meetingUTP_zh`, 3 airports × 5 languages. Empty values hide the new meeting block. Existing BKK pickup-operation guidance is retained.
- PNG saves use the voucher-only repaint boundary. Print uses a same-origin blob frame. Neither exports the whole browser nor authentication tokens.
- Landing and booking support links use existing administrator-configured channel priorities: ko KAKAO, th LINE, en/ja WHATSAPP, zh WECHAT, with existing enabled-channel fallbacks.

## English text audit

| Source | Before | After |
|---|---|---|
| step_vehicle_select.dart | server recommendation.message | localized recommendation badge / guidance |
| step_passengers_luggage.dart (two sections) | server English recommendation sentence | existing five-language customer_vehicle_guidance |
| step_confirmation.dart | KRW (원화), THB (바트) in every language | cx_currency_KRW / cx_currency_THB in five languages |
| booking_notification_section.dart | 15 default server-generated English customer notice templates | localized in five languages; booking-number suffix preserved, custom overrides unchanged |
| booking summary / voucher / assigned-driver card | raw SEDAN / Sedan type | five-language vehicle label |

T-Rider, SUV, LINE, WhatsApp/KakaoTalk configured channel names, airport/currency codes and OpenStreetMap copyright attribution are intentional names, not untranslated prose. Backend legacy recommendation messages remain for response compatibility and are no longer rendered by the booking UI.

## Assets / replacement

Original, self-authored SVGs: `frontend/assets/images/vehicle_sedan.svg`, `vehicle_suv.svg`, `vehicle_van.svg`. No competitor images were used. `CustomerVehicleArtwork.assets` in step_vehicle_select.dart is the replacement map. Add a licensed JPG/PNG/WebP under assets/images and change the relevant map path; the widget automatically chooses raster vs SVG rendering. Administrator photo upload is not added.

## Preview and QA

HTTPS: https://explorer-glenn-protective-findlaw.trycloudflare.com/

- Booking: `/booking?service=AIRPORT_PICKUP&lang=ko`
- Golf: `/booking?service=GOLF_TRANSFER&lang=ko`
- Voucher: `/booking/lookup?lang=ko`
- Admin: `/admin?lang=ko` → Settings → airport meeting instructions
- QA before assignment: TX202610170001
- QA after assignment: TX202610170002
- QA lookup phone: +66990000999 (synthetic)
- Administrator credentials: root-only `/root/tride-customer-experience-preview-credentials.json`; passwords are not included in reports/chat.

Environment: tride-customer-experience-{db,backend,preview,tunnel}, network tride-customer-experience-net, port 3121. All API responses identify `X-Preview-Backend: tride-customer-experience-backend`. SMTP and FCM credentials are absent/disabled. Existing schema/public fare snapshots were used, no production records copied. Production network remains its four production containers.

Screenshots and validation artifacts: C:/TTaxi-screens/customer-experience/ (vehicle ko/th, golf/inquiry/capacity, airport shortcuts, landing 375/1440, vouchers before/after and exported PNGs, administrator settings). QA records and preview are intentionally retained for review.

## Checks

- Backend local suite: 1,808 pass, 5 skip, 0 fail (1,813 total).
- Flutter local suite: 1,215 pass, 9 existing Windows golden failures; no baseline updates. Linux CI must be checked separately.
- Focused booking/lookup/JWT/date/flight checks: 70 pass before the final two added interaction cases; customer-experience-specific checks: 9 pass.
- Actual built frontend: three BKK→SN Plus fares 1,000/1,300/1,700; golf Siam Old 18-hole 1,600/1,900/2,300; inquiry all three 422; six-passenger unavailable tiers still priced.
- Actual guest lookup form: both QA vouchers 200, both PNG downloads successful. Wrong phone returns 404.
- Actual administrator login path: `/api/v1/auth/login`, JSON 200. Settings PUT and screen GET 200; five QA meeting texts saved only in isolated STG.

No merge or production deploy. Review first; production approval remains separate.

## Existing capacity consistency issue — review required before production

No recommendation/data correction is included. `vehicleRecommendation.service.js` first applies legacy aggregate-count rules and consults database capacity combinations only as a fallback. Isolated STG reproduces:

| Input | Existing recommendation | Active SEDAN database rule |
|---|---|---|
| 1 passenger, 1 golf bag | SEDAN selectable/recommended | max golf bags 0 |
| 2 passengers, 3 small cases | SEDAN selectable/recommended | max small cases 2 |
| 6 passengers | VAN only | SEDAN/SUV greyed out |

This was pre-existing and is now visible alongside capacity text. The explicit instruction to keep capacity data/rules unchanged takes precedence; do not silently change eligibility or hide the discrepancy. Edward/Claude should resolve whether to align the legacy recommendation rules or revise capacity data before production approval. Raw evidence: C:/TTaxi-screens/customer-experience/capacity-consistency.json.

Latest browser/CI results and screenshot gallery are provided in the local report.html. No production deploy is authorized.


## 2026-10-17 approved capacity update

Migration 76 is already deployed for golf fares. Capacity changes use 77;
76 is never overwritten. `combination_constraints` is one nullable JSON column.
SEDAN: 2 passengers / 2 small / 1 large / 2 golf; no large case with 2 golf.
SUV: 3 passengers / at most 4 cases of any size / 3 golf; cases + golf <= 6.
VAN: 8 passengers / 8 small / 8 large / 8 golf. Special luggage limits unchanged.
Recommendation and selectable vehicles now use only active DB capacity rules.
The response carries the same limits and combination constraints for display.

9,720 combinations compared to deployed legacy behavior: unavailable 0.
Unchanged 7,562; changes: SEDAN->SUV 14, SEDAN->VAN 14, SUV->SEDAN 24,
SUV->VAN 2,027, VAN->SUV 77, VAN->SEDAN 2. Total changed 2,158.
Legacy over-capacity recommendations account for movements to larger vehicles.
Explicit tests: golf2+large1=>SUV; golf3+cases3=>SUV; golf3+cases4=>VAN.

STG migration apply / rollback / reapply passed. Original three rows retained
in migration_77_capacity_backup. Rollback restores exact original maxima and
clears new constraints; retain additive nullable column and backup for safety.
Production precheck must match IDs 1/2/4 and original maxima and confirm no
existing migration_77_capacity_backup or combination_constraints before first apply.

Customer-supplied original PNGs replace the 3 vehicle illustrations unchanged.
All cards/breakdowns/voucher prices use CustomerBookingFormat.money.
Model/color/plate are inside the assigned-driver card only; upper voucher shows
only class. Search exceptions never render raw provider messages and include
support; booking controller and contact/lookup errors use localized safe text.

Production requires PR-only range, main CI, backup + Drive count verification,
77 precheck/apply, backend then frontend --no-deps, 30 minute observation.
No production booking, email, DB/proxy restart or APK change.
