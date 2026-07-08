# T-Ride Staging Domain Cutover Plan



This document describes the risk analysis and preparation plan for connecting T-Ride staging to a domain.



This is not an execution guide yet.  

Do not connect a domain until the checklist, backup plan, and rollback plan are explicitly approved.



## 1. Current State



T-Ride staging is currently running safely on temporary ports.



- Frontend: `http://103.60.127.213:3101/`

- Backend API: `http://103.60.127.213:3100/`

- Server path: `/opt/t-ride`

- Docker compose: `/opt/t-ride/deploy/docker/docker-compose.staging.yml`

- Containers:

   - `tride-db`

   - `tride-backend`

   - `tride-frontend`



Existing KTaxi legacy service is running on ports `80/443`.



- KTaxi public access: `http://103.60.127.213`

- KTaxi nginx: `ktaxi-nginx`

- KTaxi path: `/opt/ktaxi`



Current rule:



```text

T-Ride uses 3100/3101.

KTaxi keeps 80/443.



2. Absolute Safety Rules



Never touch without a separate approved execution plan:



/opt/ktaxi

ktaxi-* containers

ktaxi-nginx

/opt/ktaxi/infra/docker-compose.yml

infra_ktaxi-net

infra_\* volumes

ktaxi* volumes

ports 80/443

existing 88taxi.net vhost

certbot configuration

existing KTaxi SSL certificates



Never run:



cd /opt/ktaxi

cd /opt/ktaxi/infra

docker compose down

docker compose restart

docker restart ktaxi-nginx

docker stop ktaxi-*

docker rm ktaxi-*

docker volume rm infra_\*

docker volume rm ktaxi*

docker volume prune

docker system prune

3. Existing KTaxi Domains



Existing KTaxi legacy domains:



88taxi.net

www.88taxi.net

driver.88taxi.net

admin.88taxi.net

api.88taxi.net

ws.88taxi.net



These domains must continue to work.



Do not modify or remove their nginx config unless a full backup and rollback plan is ready.



4. Candidate T-Ride Domains



Possible future staging domains:



tride-staging.88taxi.net

tride-api-staging.88taxi.net



Alternative safer approach:



Use a completely separate domain for T-Ride staging



A separate domain or subdomain is safer than modifying existing production vhosts.



5. Domain Connection Options

Option A: Keep temporary ports only



T-Ride stays on:



http://103.60.127.213:3101/

http://103.60.127.213:3100/



Pros:



Safest option

No risk to KTaxi 80/443

No nginx or certbot change required



Cons:



Not user-friendly

No HTTPS unless separately configured

Staging URL looks temporary



Recommended for current testing.



Option B: Add new vhost to existing ktaxi-nginx



Example:



tride-staging.88taxi.net -> tride-frontend:80 or 127.0.0.1:3101

tride-api-staging.88taxi.net -> tride-backend:3000 or 127.0.0.1:3100



Pros:



Clean staging domain

Can use standard 80/443

Easier browser testing



Cons:



Touches existing ktaxi-nginx

Mistake may break KTaxi production domains

Requires careful nginx config backup

Requires SSL/certbot planning

Requires DNS and proxy configuration



Only proceed with a written backup and rollback plan.



Option C: Separate reverse proxy container for T-Ride



Run a separate T-Ride proxy on non-conflicting ports or behind an external load balancer.



Pros:



Better separation from KTaxi

Avoids changing existing legacy compose directly



Cons:



Still cannot bind host 80/443 while KTaxi owns them

Needs additional infrastructure or port mapping

HTTPS still needs planning

Option D: Separate server for T-Ride staging



Deploy T-Ride staging to a different VPS.



Pros:



Safest long-term option

No risk to KTaxi

Full control over 80/443

Cleaner domain and SSL setup



Cons:



Additional server cost

Requires new deployment setup



Best option if T-Ride will become production soon.



6. Pre-Cutover Requirements



Before any domain work:



T-Ride manual E2E must pass.

Existing KTaxi health must be confirmed.

Current nginx config must be backed up.

Current Docker state must be recorded.

DNS plan must be confirmed.

SSL/certbot plan must be confirmed.

Rollback command sequence must be prepared.

Maintenance window must be selected.

No secrets should be printed or committed.

User must explicitly approve the cutover.

7. Current Good-State Check Commands



Run before any domain-related work.



cd /opt/t-ride/deploy/docker



docker ps --format "table {{.Names}}\\t{{.Ports}}\\t{{.Status}}"



curl -i http://127.0.0.1:3100/api/v1/health

curl -I http://127.0.0.1:3101/



curl -i "http://127.0.0.1:3100/api/v1/places/autocomplete?input=pattaya\&language=ko"



Pricing checks:



curl -i -X POST http://127.0.0.1:3100/api/v1/bookings/pricing/calculate \\

   -H "Content-Type: application/json" \\

   -d '{"serviceTypeCode":"AIRPORT\_PICKUP","vehicleTypeCode":"SUV","originAirportIata":"BKK","destinationLocationCode":"PATTAYA","scheduledPickupAt":"2026-07-08T10:00:00+07:00"}'

curl -i -X POST http://127.0.0.1:3100/api/v1/bookings/pricing/calculate \\

   -H "Content-Type: application/json" \\

   -d '{"serviceTypeCode":"AIRPORT\_DROPOFF","vehicleTypeCode":"SUV","originLocationCode":"PATTAYA","destinationLocationCode":"BKK","scheduledPickupAt":"2026-07-08T10:00:00+07:00"}'



Expected:



T-Ride backend: healthy

T-Ride frontend: healthy

T-Ride DB: healthy

Google Places: 200 OK

Airport pickup pricing: 200 OK

Airport dropoff pricing: 200 OK

8. KTaxi Health Check Before Cutover



Only observe KTaxi status. Do not restart or modify.



docker ps --format "table {{.Names}}\\t{{.Ports}}\\t{{.Status}}"



Expected KTaxi containers:



ktaxi-nginx      Up healthy

ktaxi-api        Up healthy

ktaxi-realtime   Up healthy

ktaxi-worker     Up

ktaxi-redis      Up healthy

ktaxi-certbot    Up

ktaxi-minio      Up healthy

ktaxi-postgres   Up healthy



Public KTaxi should still load from:



http://103.60.127.213



If KTaxi is not healthy, do not proceed with domain work.



9. Backup Plan Before Touching Any Nginx Config



Do not execute this section unless domain cutover has been approved.



Potential backup targets:



/opt/ktaxi/infra/docker-compose.yml

existing nginx config files

existing certbot config

existing letsencrypt volume/state



Potential backup directory:



/opt/backups/ktaxi-nginx-before-tride-domain-YYYYMMDD-HHMM



Example backup approach must be reviewed before use.

Do not invent paths blindly. First inspect the existing structure safely.



Safe inspection only:



ls -la /opt/ktaxi

ls -la /opt/ktaxi/infra



Do not modify anything during inspection.



10. Rollback Requirements



Before any cutover, rollback must include:



Restore previous nginx config.

Restore previous compose file if changed.

Reload/recreate only if approved.

Verify existing KTaxi domains.

Verify T-Ride temporary ports still work.

Record exact commands used.



No cutover should begin without a rollback path.



11. Recommended Near-Term Decision



For now, keep T-Ride staging on temporary ports:



http://103.60.127.213:3101/

http://103.60.127.213:3100/



Reason:



Manual E2E is still being stabilized.

KTaxi is production-like legacy service on 80/443.

Domain work introduces unnecessary risk at this stage.



Recommended next work before domain cutover:



Finish staging manual E2E checklist.

Document account reset procedure.

Improve admin/driver operational flows.

Add more pricing route seed coverage.

Prepare domain cutover in a separate planned session.

12. Final Rule



If a command might affect any of the following, stop and ask for approval:



/opt/ktaxi

ktaxi-nginx

ktaxi-* containers

infra_\* volumes

80/443

88taxi.net nginx vhosts

certbot

legacy compose



T-Ride work should stay within:



/opt/t-ride

tride-* containers

ports 3100/3101
