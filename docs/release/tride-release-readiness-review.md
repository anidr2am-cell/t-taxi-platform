# T-Ride release readiness review

Date: 2026-07-18
Baseline `main`: `42b2e97a3bd01850e793e4d1597f3616f09fae44`

This review summarizes the remaining E2E, settlement, and operational
stabilization work prepared for T-Ride release readiness.

No PR in this series deploys staging, touches production, runs migrations,
changes Docker/nginx, or modifies KTaxi/88taxi infrastructure. All live runs
used the existing staging E2E admin/driver/customer identities only.

## Current conclusion

T-Ride now has release-gate evidence for the settlement lifecycle, customer
driver-location behavior, driver settlement UI receipt submission, admin
settlement approval UI, receipt resubmission, and cleanup safety.

Release candidate promotion can proceed to business smoke testing after the
staging frontend is rebuilt from merged `main` and operators accept the
documented staging synthetic receipt retention policy.

Completed during the PR cleanup:

1. PR #49 through PR #54 were merged in order.
2. The manual staging settlement workflow became available on `main` and was
   dispatched successfully.
3. PR #50 and PR #51 were revalidated against latest `main`, marked ready, and
   merged.
4. A final post-merge read-only staging check found no active synthetic E2E
   bookings in the default admin list, no driver settlement queue entries, and
   no active job on the shared staging E2E driver.

## Prepared PRs

| Area | PR | Branch | Head SHA | Status |
| --- | --- | --- | --- | --- |
| Manual staging settlement workflow | [#49](https://github.com/anidr2am-cell/t-taxi-platform/pull/49) | `ci/manual-staging-settlement-e2e` | `b4323eb3697ac47810f784d2174835ceb3b384b2` | Merged |
| Driver settlement UI E2E | [#50](https://github.com/anidr2am-cell/t-taxi-platform/pull/50) | `test/driver-settlement-ui-e2e` | `49fbf828ec3581576ab6550ac34c2d6668b369c3` | Merged |
| Admin settlement UI E2E | [#51](https://github.com/anidr2am-cell/t-taxi-platform/pull/51) | `test/admin-settlement-ui-e2e` | `42b2e97a3bd01850e793e4d1597f3616f09fae44` | Merged |
| Receipt rejection/resubmission E2E | [#52](https://github.com/anidr2am-cell/t-taxi-platform/pull/52) | `test/settlement-rejection-resubmission-e2e` | `7307f155f52e7f256d2daf3251960a38876445c1` | Merged |
| Full trip + settlement E2E | [#53](https://github.com/anidr2am-cell/t-taxi-platform/pull/53) | `test/full-trip-settlement-e2e` | `8869aca3fe36f5d0cf4feb9b297a6d2018cf3889` | Merged |
| Synthetic receipt retention | [#54](https://github.com/anidr2am-cell/t-taxi-platform/pull/54) | `chore/e2e-receipt-retention` | `c08d57b305d220e81525a073fe3b0c436f03d2dd` | Merged |

## Evidence collected

### Settlement lifecycle

- API-based staging lifecycle completed through GitHub Actions run
  [29639533969](https://github.com/anidr2am-cell/t-taxi-platform/actions/runs/29639533969)
  on merged `main` SHA `b4323eb3697ac47810f784d2174835ceb3b384b2`.
- Latest verified synthetic fixture: `TX202607180052`.
- Final state: booking `COMPLETED`, settlement `APPROVED`, fixture archived.
- Backend test suite: 696 passed.
- Frontend test suite after PR #51 merge: 542 passed.
- Redacted artifact `staging-settlement-lifecycle-e2e-redacted` was created.

### Driver settlement UI

- PR #50 was merged into `main` at
  `49fbf828ec3581576ab6550ac34c2d6668b369c3`.
- Browser E2E uses a local PR Flutter build with staging backend through a
  local same-origin proxy.
- The runner now opens a test-only driver settlement detail route gated by
  `TRIDE_ENABLE_E2E_ROUTES=true`, seeds the existing driver session, uses
  semantic receipt selection/upload buttons, uses a web-only native file input
  only in E2E builds, and records exactly one upload request in the manifest.
- Latest live fixture `TX202607180073` completed with receipt submitted,
  booking `COMPLETED`, settlement `APPROVED`, and cleanup archived.
- The driver amount display was corrected to render Thai baht values with the
  expected `THB` label.
- Focused revalidation after hardening:
  - `npm run test:driver-settlement-ui-e2e-tools`: 8 passed;
  - `npm run e2e:staging:driver-settlement-ui:dry-run`: passed;
  - `flutter test test/driver_settlement_test.dart test/driver_booking_detail_page_test.dart test/driver_ux_test.dart`: 16 passed on latest focused driver UI route coverage;
  - changed-file Dart analyze: no issues.

### Admin settlement UI

- PR #51 was merged into `main` at
  `42b2e97a3bd01850e793e4d1597f3616f09fae44`.
- Added a test-only admin settlement detail route gated behind
  `TRIDE_ENABLE_E2E_ROUTES=true`.
- The route now validates `bookingNumber`, keeps `AdminAuthGate`, blocks missing
  admin sessions before rendering settlement detail, and preserves the combined
  driver/admin E2E route gate in `frontend/lib/main.dart`.
- The runtime admin approval flow now requires an explicit confirmation dialog
  before approval is submitted.
- Approval confirmation was exercised through the local PR Flutter build and
  recorded exactly one approval request.
- Final live fixture `TX202607180077` passed with booking `COMPLETED`,
  settlement `APPROVED`, driver active job released, and cleanup archived.
- Partial live fixtures `TX202607180074`, `TX202607180075`, and
  `TX202607180076` were verified as synthetic `[E2E]` /
  `SETTLEMENT_LIFECYCLE_E2E` fixtures before archival cleanup.
- Focused revalidation after hardening:
  - `npm run test:admin-settlement-ui-e2e-tools`: 5 passed;
  - `npm run e2e:staging:admin-settlement-ui:dry-run`: passed;
  - `flutter test test/admin_settlement_test.dart test/admin_dispatch_test.dart`: 58 passed;
  - changed-file Dart analyze: no issues.

### Receipt rejection/resubmission

- PR #52 was merged into `main` at
  `7307f155f52e7f256d2daf3251960a38876445c1`.
- Live fixture `TX202607180047` covered:
  - V1 synthetic receipt upload;
  - admin rejection with synthetic reason;
  - driver-visible `REJECTED` state and reason;
  - V2 receipt upload;
  - old active receipt metadata no longer active;
  - admin approval candidate verification;
  - approval to `COMPLETED` / `APPROVED`;
  - driver active-job release;
  - cleanup archive.

### Full trip + settlement

- PR #53 was merged into `main` at
  `8869aca3fe36f5d0cf4feb9b297a6d2018cf3889`.
- Latest live fixture `TX202607180053` covered:
  - customer lookup browser flow at `390x844`;
  - Socket.IO connection count guard;
  - `socketIoReconnects=0`;
  - driver location marker update;
  - `ON_ROUTE`;
  - `DRIVER_ARRIVED`;
  - `PICKED_UP`;
  - `SETTLEMENT_PENDING`;
  - driver settlement money assertions;
  - synthetic receipt upload;
  - admin approval candidate verification;
  - `COMPLETED`;
  - `APPROVED`;
  - driver active job released;
  - fixture archived.

## Known limitations

1. Driver/admin settlement UI E2E routes require local or staging Flutter Web
   builds with
   `TRIDE_ENABLE_E2E_ROUTES=true`; normal production builds must keep that flag
   disabled.
2. The full trip E2E uses browser verification for customer location and API
   verification for settlement receipt/approval. It does not depend on the
   separate driver/admin settlement UI E2E tools.
3. Synthetic receipt physical files are not automatically deleted. Current code
   soft-deletes file metadata on replacement/rejection but does not remove disk
   files. PR #54 documents the safe current retention posture and future cleanup
   requirements.
4. Flutter analyze continues to report the existing unrelated 5 warning/info
   items:
   - `lib/features/booking/widgets/step_service_select.dart`
   - `test/booking_wizard_ux_test.dart`
   - `test/guest_driver_vehicle_photo_test.dart`
   - `test/review_test.dart` two unused optional-parameter warnings

## Final verification on merged main

Latest merged `main`: `42b2e97a3bd01850e793e4d1597f3616f09fae44`.

- `npm run test:e2e-tools`: 34 passed.
- `npm run test:settlement-e2e-tools`: 25 passed.
- `npm run test:settlement-rejection-e2e-tools`: 5 passed.
- `npm run test:full-trip-settlement-e2e-tools`: 7 passed.
- `npm run test:driver-settlement-ui-e2e-tools`: 8 passed.
- `npm run test:admin-settlement-ui-e2e-tools`: 5 passed.
- Backend full `npm test`: 696 passed.
- Frontend full `flutter test`: 542 passed.
- `flutter analyze --no-fatal-infos --no-fatal-warnings`: exit code 0 with
  the existing unrelated 5 warning/info items listed above.
- `flutter build web`: passed with the existing `socket_io_common` wasm
  dry-run warning.
- `git diff --check`: passed.
- Secret scan: no actual secret values found.
- Read-only staging fixture check:
  - shared E2E driver `hasActiveJob=false`;
  - shared E2E driver settlement queue count `0`;
  - default admin searches for `[E2E]`, `SETTLEMENT_LIFECYCLE_E2E`, and
    `TX20260718` returned `0` unarchived bookings.

## Release-candidate recommendation

Recommended operational sequence:

1. Rebuild/restart staging frontend from merged `main`.
2. Backend rebuild is not required for PR #50/#51/#55 because the runtime
   product changes are frontend/docs/test-tool changes only.
3. Database migration is not required.
4. Run the manual staging workflows one at a time. Do not run workflows sharing
   the staging E2E driver concurrently.
5. Perform a final read-only staging check for active E2E bookings,
   assignments, and driver active job state.
6. If clean, mark staging as release-candidate-ready for business smoke
   testing.

## Safety boundaries maintained

- No production deploy.
- No staging deploy in these PRs.
- No Docker compose up/down.
- No migration.
- No direct DB update/delete.
- No KTaxi/88taxi/nginx/80/443 changes.
- No real accounts, real payments, real receipts, QR payloads, or customer
  secrets.
- Live fixtures were synthetic and archived by the runners.
