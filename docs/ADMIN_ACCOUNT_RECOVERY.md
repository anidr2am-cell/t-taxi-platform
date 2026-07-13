# T-Ride Admin Account Recovery

This document defines safe administrator account creation and recovery rules for
production.

## Principles

- Do not store admin passwords in Git, docs, chat, tickets, screenshots, or
  terminal logs.
- Do not create demo admin accounts in production.
- Do not run seed scripts in production.
- Do not write password hashes manually through ad-hoc DB queries.
- Use the application-supported script so password hashing and role validation
  stay consistent.
- Record the recovery action in the operational audit log.

## Production initial admin

Before launch:

1. Confirm the production DB name and host.
2. Confirm `NODE_ENV=production`.
3. Confirm the operator has approval to create the first admin.
4. Generate a temporary strong password in a password manager.
5. Run the approved admin creation script on the production server with secure
   secret handling.
6. Log in once.
7. Immediately rotate the temporary password.
8. Store the final credential only in the approved password manager.

Do not put the real email or password in this document.

## Script

The repository provides:

```text
backend/scripts/createAdminUser.js
```

Use it only after confirming the production env points to the production T-Ride
DB. Do not use staging env files or demo fixtures.

Expected safe use cases:

- Create the first `SUPER_ADMIN`.
- Create an additional approved `ADMIN`.
- Reset an admin password when the account owner has been verified.

## Lost admin access

If all admins lose access:

1. Pause non-urgent admin operations.
2. Confirm incident owner approval.
3. Confirm production DB identity.
4. Confirm current Git HEAD.
5. Create a DB backup before recovery.
6. Use `createAdminUser.js` with an approved email and temporary password.
7. Require immediate password rotation after login.
8. Disable or review old admin accounts.
9. Record the action in the incident log.

## Inactive or risky admin accounts

Review production admin accounts regularly:

- Disable accounts for departed operators.
- Keep `SUPER_ADMIN` membership minimal.
- Prefer named human accounts over shared accounts.
- Review unexpected role changes.
- Review failed login patterns if available.

## Explicitly forbidden

- Direct SQL updates to insert plaintext passwords.
- Direct SQL updates to paste manually generated hashes unless approved by a
  security owner for an emergency.
- Reusing staging/demo passwords.
- Sharing admin credentials over chat or email.
- Leaving temporary passwords active after recovery.
