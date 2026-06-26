# TTaxi - Thailand Airport Transfer Platform

PWA-based airport transfer booking platform for tourists visiting Thailand.

## Tech Stack

| Layer | Technology |
|-------|------------|
| Frontend | Flutter Web (PWA) |
| Backend | Node.js + Express |
| Database | MySQL |
| Real-time | Socket.IO |
| Maps | Google Maps / Places API |
| Flights | AviationStack API |
| Push | Firebase FCM (configured separately) |

## Project Structure

```
TTaxi/
├── backend/          # Express API + Socket.IO
├── frontend/         # Flutter Web PWA
├── database/         # MySQL schema & seed data
└── README.md
```

## Quick Start

### 1. Database Setup

```bash
mysql -u root -p < database/schema.sql
```

### 2. Backend

```bash
cd backend
cp .env.example .env
# Edit .env with your DB credentials and API keys
npm install
npm start
```

API runs at `http://localhost:3000`

### 3. Frontend

```bash
cd frontend
flutter pub get
flutter run -d chrome --web-port=8080
```

## Environment Variables

| Variable | Description |
|----------|-------------|
| `DB_HOST` | MySQL host |
| `DB_USER` | MySQL user |
| `DB_PASSWORD` | MySQL password |
| `DB_NAME` | Database name (ttaxi) |
| `GOOGLE_MAPS_API_KEY` | Google Places autocomplete |
| `AVIATIONSTACK_API_KEY` | Flight status lookup |
| `FCM_SERVER_KEY` | Firebase push notifications |
| `CORS_ORIGIN` | Frontend URL (default: http://localhost:8080) |

## Features

### Customer (PWA)
- 4 service types: Airport Pickup, Dropoff, City Transfer, Golf Transfer
- Passenger & luggage input with automatic vehicle recommendation
- Name sign service (+100 THB)
- Google Places destination search
- AviationStack flight lookup (pickup)
- Vehicle selection with pricing tiers
- 3-step booking flow
- Real-time chat with driver (Socket.IO)
- 5 languages: EN, KO, ZH, JA, TH
- PWA install banner

### Admin Panel
- Dashboard (today bookings, revenue, status stats)
- Reservation management & status updates
- Live chat monitoring & participation
- Drivers, vehicle pricing, golf courses, airports
- Driver assignment workflow

## API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/airports` | List airports |
| GET | `/api/golf-courses` | List golf courses |
| POST | `/api/vehicle/recommend` | Vehicle recommendation |
| GET | `/api/vehicle/prices` | Vehicle pricing |
| GET | `/api/flight` | Flight info lookup |
| GET | `/api/places/autocomplete` | Google Places search |
| POST | `/api/reservations` | Create reservation |
| GET | `/api/reservations/:number` | Get reservation |
| GET | `/api/admin/dashboard` | Admin dashboard stats |
| GET | `/api/admin/chats` | Active chat rooms |

## Vehicle Recommendation Logic

| Condition | Vehicle |
|-----------|---------|
| ≤2 pax, ≤4 luggage, no 24"+ carrier | SEDAN |
| ≤2 pax, ≤4 luggage, has 24"+ carrier | SUV |
| ≤3 pax, ≤4 luggage | SUV |
| 4–8 pax, ≤8 luggage | VAN |
| >8 pax | Multiple vehicles auto-assigned |

## Reservation Number Format

`TXYYYYMMDD0001` (e.g. `TX202607010001`)

## Chat Rooms

Format: `room_TX202607010001` — created automatically on reservation.

Participants: customer, driver, admin (all can read and send).

## Production Build

```bash
# Frontend PWA
cd frontend
flutter build web --release

# Backend
cd backend
NODE_ENV=production npm start
```

Deploy frontend build output from `frontend/build/web` to Gabia Cloud Server with the backend API on the same or separate host.

## License

Proprietary - TTaxi
