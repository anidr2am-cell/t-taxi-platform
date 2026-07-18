# T-Ride release readiness review

Date: 2026-07-18  
Baseline `main`: `55333b45fff30327d32716cca6625f6a90453e4e`

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

1. PRs #49 through #54 are reviewed and merged in the intended order;
2. manual GitHub Actions workflows are available on the default branch after
   merge;
3. the shared staging E2E driver is idle;
4. a final post-merge staging run confirms:
   - customer driver location E2E;
   - settlement lifecycle E2E;
   - full trip + settlement E2E;
   - no active synthetic fixtures left unarchived;
5. operators accept the documented staging synthetic receipt retention policy.

## Prepared PRs

| Area | PR | Branch | Head SHA | Status |
| --- | --- | --- | --- | --- |
| Manual staging settlement workflow | [#49](https://github.com/anidr2am-cell/t-taxi-platform/pull/49) | `ci/manual-staging-settlement-e2e` | `07ec22e3e8811885e2adae3946d8698c00b24eb0` | Draft |
| Driver settlement UI E2E | [#50](https://github.com/anidr2am-cell/t-taxi-platform/pull/50) | `test/driver-settlement-ui-e2e` | `75b80a43e1e0c61abf64afcf61c149d2104a3ea8` | Draft |
| Admin settlement UI E2E | [#51](https://github.com/anidr2am-cell/t-taxi-platform/pull/51) | `test/admin-settlement-ui-e2e` | `ff10f01bec5ba9504f2e891a2c7bcd33ca7fd9e9` | Draft |
| Receipt rejection/resubmission E2E | [#52](https://github.com/anidr2am-cell/t-taxi-platform/pull/52) | `test/settlement-rejection-resubmission-e2e` | `240ba298769506cbad76b77cc8240cfa43befa32` | Draft |
| Full trip + settlement E2E | [#53](https://github.com/anidr2am-cell/t-taxi-platform/pull/53) | `test/full-trip-settlement-e2e` | `995c188804f070cc6a4fca64aa4f8d095f318d17` | Draft |
| Synthetic receipt retention | [#54](https://github.com/anidr2am-cell/t-taxi-platform/pull/54) | `chore/e2e-receipt-retention` | `a78f65773298c4d6aaf40eaa13038ad5876639fe` | Draft |

## Evidence collected

### Settlement lifecycle

- API-based staging lifecycle completed on synthetic fixture `TX202607180031`.
- Final state: booking `COMPLETED`, settlement `APPROVED`, fixture archived.
- Backend test suite: 696 passed.
- Frontend test suite during the series: 531 passed where applicable.
- Manual GitHub workflow cannot be dispatched until the workflow file exists on
  the default branch after merge.

### Driver settlement UI

- Browser E2E used a local PR Flutter build with staging backend through a
  local same-origin proxy.
- Flutter Web release semantics were not reliable enough for direct semantic
  locators; the final runner uses fixed mobile viewport interaction,
  screenshots, and API assertions.
- Live fixture `TX202607180041` completed with receipt submitted, settlement
  approved, and cleanup archived.

### Admin settlement UI

- Added a test-only admin settlement detail route gated behind
  `TRIDE_ENABLE_E2E_ROUTES=true`.
- Approval confirmation was exercised through the local PR Flutter build.
- Final live fixture `TX202607180046` passed and cleanup archived.

### Receipt rejection/resubmission

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

- Live fixture `TX202607180051` covered:
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
2. GitHub Actions workflow dispatch for new workflow files is unavailable until
   the workflow reaches the default branch.
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

1. Review and merge PR #49 to make manual workflow infrastructure available.
2. Review and merge PR #50 and PR #51 for settlement UI E2E coverage.
3. Review and merge PR #52 for rejection/resubmission coverage.
4. Review and merge PR #53 for full trip + settlement integration coverage.
5. Review and merge PR #54 so operators understand staging synthetic receipt
   retention.
6. Run the manual staging workflows one at a time. Do not run workflows sharing
   the staging E2E driver concurrently.
7. Perform a final read-only staging check for active E2E bookings,
   assignments, and driver active job state.
8. If clean, mark staging as release-candidate-ready for business smoke
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
