# T-Ride Staging Account Reset

Operator guide for safely creating or resetting T-Ride staging admin accounts.

Scope: T-Ride only (`/opt/t-ride`, `tride-*` containers).
Out of scope: legacy KTaxi (`/opt/ktaxi`, `ktaxi-*`, host 80/443).

## Safety Rules

- Do not print `.env`, JWT secrets, DB passwords, plaintext passwords, or `password_hash`.
- Do not store real staging passwords in this file, Git, tickets, or chat.
- Do not stop, restart, remove, or rebuild `ktaxi-*` containers.
- Do not restart `ktaxi-nginx`.
- Do not edit `/opt/ktaxi`.
- Do not delete Docker volumes or run clean migrations.
- Use a password manager or secure operator vault for real credentials.

## Account Model

Current identity structure:

- `users.role` is a single ENUM: `CUSTOMER`, `DRIVER`, `ADMIN`, `SUPER_ADMIN`.
- There is no roles join table.
- `users.password_hash` stores a bcrypt hash.
- `users.is_active = 1` is required for login.
- `user_profiles.user_id` stores the display name.
- Admin login uses `POST /api/v1/auth/login` with `email` and `password`.

`ADMIN` and `SUPER_ADMIN` can access protected admin features. Use `SUPER_ADMIN` only for accounts that need elevated operations.

## Script

File:

```bash
backend/scripts/createAdminUser.js
```

npm command:

```bash
npm run create-admin-user -- --email admin@tride.local --password "$ADMIN_PASSWORD" --name "T-Ride Admin" --role SUPER_ADMIN
```

Options:

- `--email` required
- `--password` required
- `--name` optional, defaults to `T-Ride Admin`
- `--role` optional, defaults to `ADMIN`
- `--force` optional, required to reset an existing account

Allowed roles:

- `ADMIN`
- `SUPER_ADMIN`

The script rejects `CUSTOMER` and `DRIVER`.

## Create A New Admin

From a local backend checkout:

```bash
cd C:\TTaxi\backend
npm run create-admin-user -- --email admin@tride.local --password "$ADMIN_PASSWORD" --name "T-Ride Admin" --role ADMIN
```

From staging Docker:

```bash
cd /opt/t-ride/deploy/docker
docker compose -f docker-compose.staging.yml exec tride-backend \
  sh -c 'cd /srv/tride/backend && npm run create-admin-user -- --email admin@tride.local --password "$ADMIN_PASSWORD" --name "T-Ride Admin" --role SUPER_ADMIN'
```

Use an environment variable or secure terminal input for `ADMIN_PASSWORD`. Do not paste real passwords into shared logs.

## Reset An Existing Admin

Existing accounts are not modified unless `--force` is present.

```bash
cd /opt/t-ride/deploy/docker
docker compose -f docker-compose.staging.yml exec tride-backend \
  sh -c 'cd /srv/tride/backend && npm run create-admin-user -- --email admin@tride.local --password "$ADMIN_PASSWORD" --name "T-Ride Admin" --role SUPER_ADMIN --force'
```

With `--force`, the script updates:

- `users.password_hash`
- `users.role`
- `users.is_active = 1`
- `user_profiles.display_name`

It does not print the plaintext password or hash.

## Verify Login

Use the normal auth endpoint. Avoid printing response tokens.

```bash
curl -s -o /dev/null -w "%{http_code}\n" \
  -X POST http://103.60.127.213:3100/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@tride.local","password":"<PASSWORD_FROM_VAULT>"}'
```

Expected result:

```text
200
```

Then verify `/admin` in the browser and check that customer center admin pages are accessible.

## Read-Only DB Check

Do not select `password_hash`.

```bash
cd /opt/t-ride/deploy/docker
docker compose -f docker-compose.staging.yml exec tride-backend \
  sh -c 'cd /srv/tride/backend && node -e "
    require(\"dotenv\").config({ path: \"/srv/tride/backend/.env\" });
    const database = require(\"./src/config/database\");
    (async () => {
      const [rows] = await database.pool.query(
        \"SELECT id, email, role, is_active FROM users WHERE email = ? AND deleted_at IS NULL\",
        [\"admin@tride.local\"]
      );
      console.log(rows[0] || \"missing\");
      await database.pool.end();
    })();
  "'
```

## Deployment Note

If only the script/docs changed:

```bash
cd /opt/t-ride
git pull origin main

cd /opt/t-ride/deploy/docker
docker compose -f docker-compose.staging.yml up -d --build tride-backend
```

No DB migration is required.

Do not rebuild `tride-frontend` unless frontend files changed in the same deployment.

## Forbidden Commands

Do not run:

```bash
docker compose down
docker compose down -v
docker volume rm tride_mysql_data
docker restart ktaxi-nginx
docker stop ktaxi-*
cd /opt/ktaxi
cat .env
SELECT password_hash FROM users
```

## Sign-Off

| Check | Result |
|-------|--------|
| Admin account created or reset | |
| `/api/v1/auth/login` returns 200 | |
| `/admin` accessible | |
| Customer center admin menu accessible | |
| KTaxi untouched | |
