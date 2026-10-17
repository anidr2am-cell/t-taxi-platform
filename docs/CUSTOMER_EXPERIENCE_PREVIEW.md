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
