\# T-Ride Staging Manual E2E Checklist



This checklist is for manually verifying T-Ride staging on Gabia.



\## Scope



This checklist applies only to T-Ride staging.



\* Frontend: `http://103.60.127.213:3101/`

\* Backend API: `http://103.60.127.213:3100/`

\* Server path: `/opt/t-ride`

\* Docker compose: `/opt/t-ride/deploy/docker/docker-compose.staging.yml`



Do not use plain `http://103.60.127.213` for T-Ride.

That address uses port `80` and belongs to the existing KTaxi legacy service.



\## Absolute Safety Rules



Never touch:



\* `/opt/ktaxi`

\* `ktaxi-\*` containers

\* `ktaxi-nginx`

\* `infra\_\*` volumes

\* `ktaxi\*` volumes

\* ports `80/443`

\* legacy compose files

\* `.env` secret values

\* DB volumes

\* clean migration



Never run:



```bash

cd /opt/ktaxi

docker restart ktaxi-nginx

docker stop ktaxi-\*

docker rm ktaxi-\*

docker volume rm infra\_\*

docker volume rm ktaxi\*

docker volume prune

docker system prune

```



\## 1. Server Health Check



Run on Gabia server:



```bash

cd /opt/t-ride/deploy/docker



docker ps --format "table {{.Names}}\\t{{.Ports}}\\t{{.Status}}"



curl -i http://127.0.0.1:3100/api/v1/health

curl -I http://127.0.0.1:3101/

```



Expected:



\* `tride-backend`: Up healthy

\* `tride-frontend`: Up healthy

\* `tride-db`: Up healthy

\* Backend health: `200 OK`

\* Frontend: `200 OK`

\* Existing `ktaxi-\*` containers remain running



\## 2. Google Places Check



Run:



```bash

curl -i "http://127.0.0.1:3100/api/v1/places/autocomplete?input=pattaya\&language=ko"

```



Expected:



\* `HTTP/1.1 200 OK`

\* `success: true`

\* predictions returned



\## 3. Airport Pickup Pricing Check



Run:



```bash

curl -i -X POST http://127.0.0.1:3100/api/v1/bookings/pricing/calculate \\

&#x20; -H "Content-Type: application/json" \\

&#x20; -d '{"serviceTypeCode":"AIRPORT\_PICKUP","vehicleTypeCode":"SUV","originAirportIata":"BKK","destinationLocationCode":"PATTAYA","scheduledPickupAt":"2026-07-08T10:00:00+07:00"}'

```



Expected:



\* `HTTP/1.1 200 OK`

\* `success: true`

\* `totalAmount` exists

\* `routeId` exists

\* `vehiclePriceId` exists



\## 4. Airport Dropoff Pricing Check



Run:



```bash

curl -i -X POST http://127.0.0.1:3100/api/v1/bookings/pricing/calculate \\

&#x20; -H "Content-Type: application/json" \\

&#x20; -d '{"serviceTypeCode":"AIRPORT\_DROPOFF","vehicleTypeCode":"SUV","originLocationCode":"PATTAYA","destinationLocationCode":"BKK","scheduledPickupAt":"2026-07-08T10:00:00+07:00"}'

```



Expected:



\* `HTTP/1.1 200 OK`

\* `success: true`

\* `totalAmount` exists

\* `routeId` exists

\* `vehiclePriceId` exists



\## 5. Browser Access Check



Open:



```text

http://103.60.127.213:3101/

```



Expected:



\* T-Ride frontend opens

\* Do not use `http://103.60.127.213` without port `3101`



\## 6. Customer Airport Pickup Booking Flow



Browser flow:



1\. Open `http://103.60.127.213:3101/`

2\. Select airport pickup

3\. Origin: Suvarnabhumi Airport / BKK

4\. Destination: Pattaya

5\. Select pickup date/time

6\. Enter passenger information

7\. Enter customer information

8\. Confirm vehicle section unlocks

9\. Confirm vehicle prices appear

10\. Select vehicle

11\. Submit booking

12\. Confirm booking number is displayed



Expected:



\* No `Google Places provider is not configured`

\* No `Route not found for the given service and locations`

\* Booking creation succeeds

\* Booking number is shown



\## 7. Customer Airport Dropoff Booking Flow



Browser flow:



1\. Open `http://103.60.127.213:3101/`

2\. Select airport dropoff

3\. Origin: Pattaya

4\. Destination: Suvarnabhumi Airport / BKK

5\. Select pickup date/time

6\. Enter passenger information

7\. Enter customer information

8\. Confirm vehicle section unlocks

9\. Confirm vehicle prices appear

10\. Select vehicle

11\. Submit booking

12\. Confirm booking number is displayed



Expected:



\* Vehicle pricing works

\* No route-not-found error

\* Booking creation succeeds

\* Booking number is shown



\## 8. Booking Lookup Flow



Open:



```text

http://103.60.127.213:3101/booking/lookup

```



Check:



1\. Enter booking number

2\. Enter customer phone number

3\. Submit lookup



Expected:



\* Booking detail appears

\* Trip information is correct

\* Status is displayed correctly

\* Customer guidance text appears



\## 9. Admin Flow



Open:



```text

http://103.60.127.213:3101/admin

```



Check:



1\. Admin login

2\. Booking list loads

3\. Newly created booking appears

4\. Booking detail opens

5\. Driver assignment action is available

6\. Assign driver

7\. Confirm assigned driver appears in booking detail/list



Expected:



\* Admin login works

\* Booking list/detail works

\* Driver assignment works



\## 10. Driver Flow



Open:



```text

http://103.60.127.213:3101/driver

```



Check:



1\. Driver login

2\. Today's assigned bookings appear

3\. Open assigned booking

4\. Change status to `ON\_ROUTE`

5\. Change status to `DRIVER\_ARRIVED`

6\. Change status to `COMPLETED`

7\. Confirm completed booking is read-only or removed from active list



Expected:



\* Driver login works

\* Assigned jobs appear

\* Status buttons call real API mutations

\* List refreshes after successful action



\## 11. Final Server Check



After manual E2E, run:



```bash

cd /opt/t-ride/deploy/docker



docker ps --format "table {{.Names}}\\t{{.Ports}}\\t{{.Status}}"



curl -i http://127.0.0.1:3100/api/v1/health

curl -I http://127.0.0.1:3101/

```



Expected:



\* `tride-\*` containers remain healthy

\* `ktaxi-\*` containers remain running

\* Backend health remains `200 OK`

\* Frontend remains `200 OK`



\## 12. Pass Criteria



Manual E2E is considered passed when all of the following are true:



\* Server health OK

\* Frontend OK

\* Google Places OK

\* Airport pickup pricing OK

\* Airport dropoff pricing OK

\* Airport pickup booking creation OK

\* Airport dropoff booking creation OK

\* Booking lookup OK

\* Admin booking list/detail OK

\* Admin driver assignment OK

\* Driver assigned job list OK

\* Driver status transitions OK

\* Existing KTaxi legacy stack unaffected



\## 13. Failure Notes



If `Google Places provider is not configured` appears:



\* Check server `.env` for `GOOGLE\_PLACES\_API\_KEY` or `GOOGLE\_MAPS\_API\_KEY`

\* Do not print the actual key value

\* Rebuild `tride-backend` if needed



If `Route not found for the given service and locations` appears:



\* Check pricing payload

\* Check pickup/dropoff direction

\* Check `database/21\_pricing\_seed\_repair.sql`

\* Run migration only through `tride-backend`

\* Do not delete DB volume



If browser still shows old behavior after a frontend fix:



\* Rebuild `tride-frontend`

\* Test in incognito mode

\* Clear site data for `103.60.127.213`



\## 14. Current Known Good Access



```text

KTaxi legacy:

http://103.60.127.213



T-Ride staging:

http://103.60.127.213:3101/



T-Ride backend API:

http://103.60.127.213:3100/

```



