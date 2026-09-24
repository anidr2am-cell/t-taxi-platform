/**
 * Local-only mock API for admin manual QA (no production data).
 * Run: node frontend/qa/mock_admin_api_server.mjs
 * Listens: http://127.0.0.1:3099
 */
import http from 'node:http';
import { URL } from 'node:url';

const PORT = 3099;
const HOST = '127.0.0.1';

/** @type {Record<string, object>} */
const bookings = {
  TX202609240001: buildBookingDetail(),
  TX202609240003: buildBookingDetail({ bookingNumber: 'TX202609240003' }),
};

/** @type {{ method: string, path: string, body: unknown } | null} */
let lastManualPatch = null;
/** @type {{ driverId: number, bookingNumber: string } | null} */
let lastAssignRequest = null;

function buildBookingDetail(overrides = {}) {
  return {
    bookingNumber: 'TX202609240001',
    status: 'OPEN',
    commissionStatus: 'NOT_DUE_YET',
    createdAt: '2026-09-23T10:00:00.000Z',
    updatedAt: '2026-09-23T10:00:00.000Z',
    statusHistory: [],
    bookingSource: 'ADMIN_MANUAL',
    scheduledPickupAt: '2026-09-24T03:00:00.000Z', // 10:00 Bangkok
    specialRequests: 'QA memo text',
    manualCallActions: { canEdit: true, canCancel: true, canAssign: true },
    serviceType: { code: 'AIRPORT_PICKUP', name: 'Airport Pickup' },
    route: {
      origin: {
        address: '999 Virtual Airport Rd',
        placeId: 'qa-origin-place',
        lat: '13.6900',
        lng: '100.7501',
        name: 'Suvarnabhumi QA',
        nameTh: 'สนามบินทดสอบ',
      },
      destination: {
        address: 'Virtual Pattaya Beach',
        placeId: 'qa-dest-place',
        lat: '12.9236',
        lng: '100.8825',
        name: 'Pattaya QA',
        nameTh: 'พัทยาทดสอบ',
      },
    },
    vehicle: { typeCode: 'VAN', typeName: 'Van', count: 1 },
    passengers: { adults: 2, children: 1, infants: 0 },
    luggage: {
      carriers20Inch: 1,
      carriers24InchPlus: 2,
      golfBags: 0,
      specialItems: 'wheelchair foldable',
    },
    options: { preferFemaleDriver: true, nameSign: false, nameSignText: null },
    customer: {
      customerUserId: 9001,
      name: 'QA Guest Kim',
      phone: '+66800000001',
      email: 'qa-guest@example.test',
    },
    pricing: {
      paymentMethod: 'PAY_DRIVER',
      paymentStatus: 'UNPAID',
      totalAmount: 1200,
      currency: 'THB',
      chargeItems: [
        {
          chargeType: 'OTHER',
          description: 'Admin manual payout',
          quantity: 1,
          unitPrice: '850',
          amount: '850',
        },
      ],
    },
    flight: {
      flightNumber: 'TG123',
      airportIata: 'BKK',
      scheduledArrivalAt: '2026-09-24 12:00:00',
      estimatedArrivalAt: '2026-09-24 12:15:00',
      golfCourseId: null,
      golfRegion: null,
      driverIncluded: false,
    },
    allowedActions: ['ASSIGN_DRIVER', 'VIEW_DETAILS'],
    primaryCta: 'ASSIGN_DRIVER',
    operations: { primaryCta: 'ASSIGN_DRIVER' },
    ...overrides,
  };
}

function json(res, status, body) {
  const payload = JSON.stringify(body);
  res.writeHead(status, {
    'Content-Type': 'application/json',
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'Content-Type, Authorization, Accept',
    'Access-Control-Allow-Methods': 'GET,POST,PATCH,OPTIONS',
  });
  res.end(payload);
}

function readBody(req) {
  return new Promise((resolve) => {
    const chunks = [];
    req.on('data', (c) => chunks.push(c));
    req.on('end', () => {
      const raw = Buffer.concat(chunks).toString('utf8');
      if (!raw) return resolve(null);
      try {
        resolve(JSON.parse(raw));
      } catch {
        resolve(null);
      }
    });
  });
}

function listDrivers(bookingNumber) {
  const base = [
    {
      driverId: 101,
      displayName: 'QA Active No Conflict',
      phone: '+66801000001',
      eligibilityState: 'AVAILABLE',
      activeAssignmentCount: 1,
      assignmentEligible: true,
      pickupTimeConflict: false,
    },
    {
      driverId: 102,
      displayName: 'QA Conflict Exactly 60m',
      phone: '+66801000002',
      eligibilityState: 'AVAILABLE',
      activeAssignmentCount: 1,
      assignmentEligible: false,
      pickupTimeConflict: true,
    },
    {
      driverId: 103,
      displayName: 'QA Gap 61m OK',
      phone: '+66801000003',
      eligibilityState: 'AVAILABLE',
      activeAssignmentCount: 1,
      assignmentEligible: true,
      pickupTimeConflict: false,
    },
    {
      driverId: 104,
      displayName: 'QA Settlement Blocked',
      phone: '+66801000004',
      eligibilityState: 'BLOCKED',
      activeAssignmentCount: 0,
      assignmentEligible: false,
      pickupTimeConflict: false,
      blockReason: 'Outstanding commission settlement',
    },
  ];
  if (bookingNumber === 'TX202609240002') {
    return base.map((d) =>
      d.driverId === 101
        ? { ...d, assignmentEligible: true, pickupTimeConflict: false }
        : d,
    );
  }
  if (bookingNumber === 'TX202609240003') {
    return [
      ...base.filter((d) => d.assignmentEligible && !d.pickupTimeConflict),
      {
        driverId: 199,
        displayName: 'QA API Conflict On Submit',
        phone: '+66801000199',
        eligibilityState: 'AVAILABLE',
        activeAssignmentCount: 0,
        assignmentEligible: true,
        pickupTimeConflict: false,
      },
    ];
  }
  return base;
}

const slowFlightTimers = new Map();

const server = http.createServer(async (req, res) => {
  if (req.method === 'OPTIONS') {
    return json(res, 204, {});
  }

  const url = new URL(req.url, `http://${HOST}:${PORT}`);
  const path = url.pathname;

  if (path === '/api/v1/auth/login' && req.method === 'POST') {
    return json(res, 200, {
      data: {
        accessToken: 'qa-mock-admin-token',
        user: { id: 1, role: 'ADMIN', email: 'qa-admin@example.test' },
      },
    });
  }

  if (path === '/api/golf-regions' && req.method === 'GET') {
    return json(res, 200, ['East', 'West']);
  }

  if (path === '/api/golf-courses' && req.method === 'GET') {
    return json(res, 200, [
      { id: 501, name: 'QA Golf East', region: url.searchParams.get('region') ?? 'East' },
      { id: 502, name: 'QA Golf East 2', region: 'East' },
    ]);
  }

  if (path === '/api/v1/places/autocomplete' && req.method === 'GET') {
    return json(res, 200, {
      data: {
        predictions: [
          {
            placeId: 'qa-autocomplete-1',
            description: 'QA Place One, Bangkok',
            mainText: 'QA Place One',
            secondaryText: 'Bangkok',
          },
        ],
      },
    });
  }

  if (path === '/api/v1/places/details' && req.method === 'GET') {
    return json(res, 200, {
      data: {
        placeId: url.searchParams.get('placeId') ?? 'qa-place',
        name: 'QA Place Detail',
        formattedAddress: 'QA Address Line, Bangkok',
        lat: 13.75,
        lng: 100.5,
      },
    });
  }

  if (path === '/api/v1/public/flights/search' && req.method === 'GET') {
    const flightNumber = (url.searchParams.get('flightNumber') ?? '').toUpperCase();
    const flightDate = url.searchParams.get('flightDate') ?? '';

    if (flightNumber === 'NOTFOUND') {
      return json(res, 404, {
        message: 'Flight not found',
        error_code: 'FLIGHT_NOT_FOUND',
      });
    }

    if (flightNumber === 'SLOWOLD') {
      const key = `${flightNumber}:${flightDate}`;
      if (!slowFlightTimers.has(key)) {
        slowFlightTimers.set(key, setTimeout(() => {}, 2500));
        await new Promise((r) => setTimeout(r, 2500));
      }
      return json(res, 200, {
        data: {
          flightNumber: 'SLOWOLD',
          airlineName: 'QA Airways',
          departure: {
            airportCode: 'ICN',
            scheduledAt: `${flightDate}T01:00:00.000Z`,
          },
          arrival: {
            airportCode: 'BKK',
            scheduledAt: `${flightDate}T08:00:00.000Z`,
            estimatedAt: `${flightDate}T08:05:00.000Z`,
          },
        },
      });
    }

    // Default TG123: arrival 12:00 Bangkok = 05:00 UTC on same calendar day as flightDate
    const scheduledArrival = `${flightDate}T05:00:00.000Z`;
    return json(res, 200, {
      data: {
        flightNumber,
        airlineName: 'QA Thai',
        departure: {
          airportCode: 'ICN',
          scheduledAt: `${flightDate}T01:00:00.000Z`,
        },
        arrival: {
          airportCode: 'BKK',
          scheduledAt: scheduledArrival,
          estimatedAt: `${flightDate}T05:10:00.000Z`,
        },
      },
    });
  }

  if (path === '/api/v1/admin/drivers' && req.method === 'GET') {
    const bookingNumber = url.searchParams.get('bookingNumber') ?? '';
    return json(res, 200, { data: listDrivers(bookingNumber) });
  }

  const bookingNotesMatch = path.match(
    /^\/api\/v1\/admin\/bookings\/(TX\d{12})\/notes$/,
  );
  if (bookingNotesMatch && req.method === 'GET') {
    return json(res, 200, { data: { items: [], page: 1, limit: 20, total: 0 } });
  }

  const bookingDetailMatch = path.match(/^\/api\/v1\/admin\/bookings\/(TX\d{12})$/);
  if (bookingDetailMatch && req.method === 'GET') {
    const num = bookingDetailMatch[1];
    const detail = bookings[num] ?? buildBookingDetail({ bookingNumber: num });
    return json(res, 200, { data: detail });
  }

  const manualPatchMatch = path.match(
    /^\/api\/v1\/admin\/bookings\/(TX\d{12})\/manual$/,
  );
  if (manualPatchMatch && req.method === 'PATCH') {
    const num = manualPatchMatch[1];
    const body = await readBody(req);
    lastManualPatch = { method: 'PATCH', path, body };
    const existing = bookings[num] ?? buildBookingDetail({ bookingNumber: num });
    if (body?.memo != null) {
      existing.specialRequests = body.memo;
    }
    bookings[num] = existing;
    return json(res, 200, {
      data: {
        bookingNumber: num,
        status: existing.status,
        payoutAmount: 850,
      },
    });
  }

  const assignMatch = path.match(
    /^\/api\/v1\/admin\/bookings\/(TX\d{12})\/assign-driver$/,
  );
  if (assignMatch && req.method === 'POST') {
    const num = assignMatch[1];
    const body = await readBody(req);
    lastAssignRequest = { driverId: body?.driverId, bookingNumber: num };
    if (body?.driverId === 199) {
      return json(res, 409, {
        message: 'Another assigned job is too close to this pickup time',
        error_code: 'DRIVER_BOOKING_TIME_CONFLICT',
      });
    }
    return json(res, 200, {
      data: { assignmentId: 555, bookingStatus: 'DRIVER_ASSIGNED' },
    });
  }

  if (path === '/api/v1/qa/last-manual-patch' && req.method === 'GET') {
    return json(res, 200, { data: lastManualPatch });
  }

  if (path === '/api/v1/qa/last-assign' && req.method === 'GET') {
    return json(res, 200, { data: lastAssignRequest });
  }

  json(res, 404, { message: `Mock route not found: ${req.method} ${path}` });
});

server.listen(PORT, HOST, () => {
  console.log(`Admin manual QA mock API at http://${HOST}:${PORT}`);
});
