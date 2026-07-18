# T-Ride release readiness review

Date: 2026-07-18
Baseline `main`: `c08d57b305d220e81525a073fe3b0c436f03d2dd`

This review summarizes the remaining E2E, settlement, and operational
stabilization work prepared for T-Ride release readiness.

No PR in this series deploys staging, touches production, runs migrations,
changes Docker/nginx, or modifies KTaxi/88taxi infrastructure. All live runs
used the existing staging E2E admin/driver/customer identities only.

## Current conclusion

T-Ride has substantially better release evidence after this series, especially
around settlement lifecycle, customer driver-location behavior, receipt
resubmission, and cleanup safety.

Release candidate promotion should still wait until:

1. PR #50 and PR #51 are either merged after review or explicitly deferred from
   the release gate;
2. the shared staging E2E driver is idle;
3. a final post-merge staging run confirms:
   - customer driver location E2E;
   - settlement lifecycle E2E;
   - full trip + settlement E2E;
   - no active synthetic fixtures left unarchived;
4. operators accept the documented staging synthetic receipt retention policy.

Completed during the PR cleanup:

1. PR #49, #52, #53, and #54 were merged in order.
2. The manual staging settlement workflow became available on `main` and was
   dispatched successfully.

## Prepared PRs

| Area | PR | Branch | Head SHA | Status |
| --- | --- | --- | --- | --- |
| Manual staging settlement workflow | [#49](https://github.com/anidr2am-cell/t-taxi-platform/pull/49) | `ci/manual-staging-settlement-e2e` | `b4323eb3697ac47810f784d2174835ceb3b384b2` | Merged |
| Driver settlement UI E2E | [#50](https://github.com/anidr2am-cell/t-taxi-platform/pull/50) | `test/driver-settlement-ui-e2e` | `a672666afc56d6b889977fd0cbc6b0d8ae20680c` | Draft, open |
| Admin settlement UI E2E | [#51](https://github.com/anidr2am-cell/t-taxi-platform/pull/51) | `test/admin-settlement-ui-e2e` | `0f3300cbcda58fcba675d2a9cfe94db77f9ab468` | Draft, open |
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
- Frontend test suite during the series: 531 passed where applicable.
- Redacted artifact `staging-settlement-lifecycle-e2e-redacted` was created.

### Driver settlement UI

- PR #50 remains draft and was updated after the main merges.
- Browser E2E uses a local PR Flutter build with staging backend through a
  local same-origin proxy.
- The runner now opens a test-only driver settlement detail route gated by
  `TRIDE_ENABLE_E2E_ROUTES=true`, seeds the existing driver session, uses
  semantic receipt selection/upload buttons, and records one file chooser click
  and one upload click in the manifest.
- Live fixture `TX202607180041` completed with receipt submitted, settlement
  approved, and cleanup archived.
- Focused revalidation after hardening:
  - `npm run test:driver-settlement-ui-e2e-tools`: 8 passed;
  - `npm run e2e:staging:driver-settlement-ui:dry-run`: passed;
  - `flutter test test/driver_settlement_test.dart test/driver_booking_detail_page_test.dart test/driver_ux_test.dart`: 77 passed;
  - changed-file Dart analyze: no issues.

### Admin settlement UI

- PR #51 remains draft and was updated after the main merges.
- Added a test-only admin settlement detail route gated behind
  `TRIDE_ENABLE_E2E_ROUTES=true`.
- The route now validates `bookingNumber`, keeps `AdminAuthGate`, blocks missing
  admin sessions before rendering settlement detail, and uses semantic approve
  buttons instead of coordinate loops.
- Approval confirmation was exercised through the local PR Flutter build.
- Final live fixture `TX202607180046` passed and cleanup archived.
- Focused revalidation after hardening:
  - `npm run test:admin-settlement-ui-e2e-tools`: 5 passed;
  - `npm run e2e:staging:admin-settlement-ui:dry-run`: passed;
  - `flutter test test/admin_settlement_test.dart`: 6 passed;
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

1. PRs are intentionally separate and based on current `main`; they are not
   stacked. Some combined capabilities require post-merge verification.
2. PR #50 and PR #51 require local or staging Flutter Web builds with
   `TRIDE_ENABLE_E2E_ROUTES=true`; normal production builds must keep that flag
   disabled.
3. The full trip E2E uses browser verification for customer location and API
   verification for settlement receipt/approval. It does not depend on the
   separate unmerged driver/admin settlement UI E2E PRs.
4. Synthetic receipt physical files are not automatically deleted. Current code
   soft-deletes file metadata on replacement/rejection but does not remove disk
   files. PR #54 documents the safe current retention posture and future cleanup
   requirements.
5. Flutter analyze continues to report the existing unrelated 5 warning/info
   items:
   - `lib/features/booking/widgets/step_service_select.dart`
   - `test/booking_wizard_ux_test.dart`
   - `test/guest_driver_vehicle_photo_test.dart`
   - `test/review_test.dart` two unused optional-parameter warnings

## Merge and verification recommendation

Recommended sequence:

1. Keep PR #50 and PR #51 in draft until the team is ready to run the local
   Flutter Web E2E builds with `TRIDE_ENABLE_E2E_ROUTES=true`, then mark ready
   or explicitly defer them.
2. Run the manual staging workflows one at a time. Do not run workflows sharing
   the staging E2E driver concurrently.
3. Perform a final read-only staging check for active E2E bookings,
   assignments, and driver active job state.
4. If clean, mark staging as release-candidate-ready for business smoke
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
