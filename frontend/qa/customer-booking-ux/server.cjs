// Isolated QA: synthetic fixtures only, no DB, SMTP, sockets or production proxy.
const http = require("node:http"),
  fs = require("node:fs"),
  path = require("node:path");
const root = path.resolve(__dirname, "../../.."),
  landing = root + "/landing/dist",
  web = root + "/frontend/build/web";
const contacts = JSON.parse(
  fs.readFileSync(path.join(__dirname, "public-channels.json")),
);
const landingData = JSON.parse(
  fs.readFileSync(path.join(__dirname, "landing-data.json")),
);
const V = require(
  root + "/backend/src/services/vehicleRecommendation.service.js",
);
const rules = [
  ["SEDAN", 2, 2, 1, 2, { noLargeAtGolf: 2 }],
  ["SUV", 3, 4, 4, 3, { maxCases: 4, maxCasesAndGolf: 6 }],
  ["VAN", 8, 8, 8, 8, {}],
].map(([code, p, s, l, g, c], i) => ({
  code,
  max_passengers: p,
  max_carriers_20_inch: s,
  max_carriers_24_inch_plus: l,
  max_golf_bags: g,
  max_special_luggage: 0,
  combination_constraints: c,
  sort_order: i,
}));
const vehicles = rules.map((r) => ({ code: r.code, sort_order: r.sort_order }));
const service = new V({
  findActiveTypesOrdered: async () => vehicles,
  findActiveCapacityRules: async () => rules,
});
const seen = new Map();
let sequence = 0;
const mime = {
  ".html": "text/html",
  ".css": "text/css",
  ".js": "application/javascript",
  ".png": "image/png",
  ".webp": "image/webp",
  ".json": "application/json",
  ".wasm": "application/wasm",
  ".woff2": "font/woff2",
  ".ttf": "font/ttf",
  ".svg": "image/svg+xml",
};
http
  .createServer(async (q, r) => {
    r.setHeader("X-Preview-Backend", "customer-booking-ux-20261121-fixture");
    r.setHeader("Cache-Control", "no-store");
    const u = new URL(q.url, "http://localhost");
    const json = (data, code = 200) => {
      r.statusCode = code;
      r.setHeader("Content-Type", "application/json");
      r.end(JSON.stringify(data));
    };
    if (u.pathname === "/qa/status")
      return json({
        synthetic: true,
        createdBookings: sequence,
        idempotencyKeys: seen.size,
      });
    if (u.pathname === "/api/v1/settings/assets/contactWechatQr") {
      r.setHeader(
        "Content-Type",
        fs
          .readFileSync(path.join(__dirname, "wechat-qr-type.txt"), "utf8")
          .trim(),
      );
      return fs.createReadStream(path.join(__dirname, "wechat-qr.bin")).pipe(r);
    }
    if (u.pathname.startsWith("/api/")) {
      let text = "";
      for await (const chunk of q) text += chunk;
      let body = {};
      try {
        body = JSON.parse(text || "{}");
      } catch {
        return json({ success: false }, 400);
      }
      const ok = (data) => json({ success: true, data });
      if (
        /\/bookings\/QA-PREVIEW-\d+\/contact-connection(s(?:\/confirm-sent)?)?$/.test(
          u.pathname,
        )
      ) {
        const number = u.pathname.match(/QA-PREVIEW-\d+/)[0],
          row = [...seen.values()].find((x) => x.bookingNumber === number);
        if (!row) return json({ success: false }, 404);
        if (u.pathname.endsWith("/confirm-sent"))
          row.contactStatus = "CONFIRM_REQUESTED";
        if (body.channel) row.contactChannel = body.channel;
        return ok({
          bookingNumber: number,
          bookingStatus: row.status,
          contactStatus: row.contactStatus,
          contactChannel: row.contactChannel,
          contactChannelManaged: false,
          contactConnectionRequired: true,
          paymentMethod: row.paymentMethod,
          paymentStatus: row.paymentStatus,
          totalAmount: row.totalAmount,
          currency: "THB",
        });
      }
      if (u.pathname.endsWith("/public/landing-data")) return json(landingData);
      if (u.pathname.endsWith("/contact-channels/public"))
        return json(contacts);
      if (u.pathname.endsWith("/airports"))
        return ok(["BKK", "DMK", "UTP"].map((code) => ({ code })));
      if (u.pathname.endsWith("/vehicles/types")) return ok(vehicles);
      if (u.pathname.endsWith("/vehicle/recommend"))
        return ok(await service.recommend(body));
      if (u.pathname.endsWith("/pricing/calculate")) {
        if (body.destinationLocationCode === "UNKNOWN")
          return json(
            {
              success: false,
              code: "PRICING_INQUIRY_REQUIRED",
              error_code: "PRICING_INQUIRY_REQUIRED",
            },
            422,
          );
        const prices =
          body.serviceTypeCode === "GOLF_TRANSFER"
            ? [1600, 1900, 2300]
            : [1000, 1300, 1700];
        const base =
          prices[["SEDAN", "SUV", "VAN"].indexOf(body.vehicleTypeCode)] || 1000;
        const sign = body.options?.nameSign ? 100 : 0;
        return ok({
          currency: "THB",
          totalAmount: base + sign,
          chargeItems: [
            {
              chargeType: "VEHICLE_BASE",
              amount: base,
              quantity: 1,
              unitPrice: base,
              description: "QA",
            },
            ...(sign
              ? [
                  {
                    chargeType: "NAME_SIGN",
                    amount: sign,
                    quantity: 1,
                    unitPrice: sign,
                    description: "QA",
                  },
                ]
              : []),
          ],
        });
      }
      if (u.pathname.endsWith("/places/autocomplete"))
        return ok({
          predictions: [
            {
              placeId: "qa-hotel",
              mainText: "QA Hotel",
              secondaryText: "Pattaya, Thailand",
            },
          ],
        });
      if (u.pathname.endsWith("/places/details"))
        return ok({
          name: "QA Hotel",
          formattedAddress: "QA Pattaya, Thailand",
          lat: 12.936,
          lng: 100.886,
        });
      if (u.pathname.endsWith("/public/flights/search"))
        return ok({
          results: [
            {
              flightNumber: u.searchParams.get("flightNumber") || "QA101",
              departure: {
                airportCode: "ICN",
                scheduledAt: "2026-12-10T12:00:00Z",
                scheduledLocal: "2026-12-10T21:00:00+09:00",
              },
              arrival: {
                airportCode: "BKK",
                scheduledAt: "2026-12-10T17:40:00Z",
                scheduledLocal: "2026-12-11T00:40:00+07:00",
              },
            },
          ],
        });
      if (u.pathname.endsWith("/golf-courses"))
        return ok([
          {
            id: 1,
            name: "QA Siam Old",
            names: {
              en: "QA Siam Old",
              ko: "QA 시암 올드",
              ja: "QA サイアム オールド",
              zh: "QA 暹罗老球场",
            },
            latitude: 12.918,
            longitude: 100.98,
            groupCode: "A",
          },
        ]);
      if (u.pathname === "/api/v1/bookings" && q.method === "POST") {
        const key = q.headers["idempotency-key"];
        if (!key) return json({ success: false }, 400);
        if (!seen.has(key))
          seen.set(key, {
            bookingId: ++sequence,
            bookingNumber: "QA-PREVIEW-" + sequence,
            status: "CONFIRMED",
            paymentMethod: body.paymentMethod || "PAY_DRIVER",
            paymentStatus: "UNPAID",
            totalAmount: 1000,
            currency: "THB",
            guestAccessToken: "qa-preview-only",
            contactStatus: "PENDING",
            contactChannel: body.customer?.messengerType || "LINE",
            contactConnectionRequired: false,
            canCancel: true,
            cancellationDeadline: "2026-12-10T08:30:00+07:00",
          });
        return ok(seen.get(key));
      }
      if (u.pathname.endsWith("/gate-arrival"))
        return ok({
          eligible: true,
          canNotify: false,
          reason: "OUTSIDE_ARRIVAL_WINDOW",
          gate: "7",
          sent: false,
        });
      if (u.pathname.includes("meeting")) return ok({});
      if (u.pathname.includes("notification")) return ok([]);
      if (u.pathname.includes("home-banner")) return ok([]);
      if (u.pathname.includes("/settings/")) return ok({});
      return json(
        {
          success: false,
          message: "QA fixture: unavailable",
          code: "QA_FIXTURE_UNAVAILABLE",
        },
        404,
      );
    }
    let f;
    if (
      ["/", "/en/", "/ko/", "/ja/", "/th/", "/zh/", "/zh-TW/"].includes(
        u.pathname,
      )
    )
      f =
        u.pathname === "/"
          ? path.join(landing, "index.html")
          : path.join(landing, u.pathname, "index.html");
    else if (u.pathname.startsWith("/landing-assets/"))
      f = path.join(landing, u.pathname);
    else f = path.join(web, decodeURIComponent(u.pathname));
    if (path.relative(root, f).startsWith("..")) {
      r.statusCode = 403;
      return r.end();
    }
    if (!fs.existsSync(f) || !fs.statSync(f).isFile())
      f = path.join(web, "index.html");
    if (!fs.existsSync(f)) {
      r.statusCode = 503;
      return r.end("Preview build in progress");
    }
    r.setHeader(
      "Content-Type",
      mime[path.extname(f)] || "application/octet-stream",
    );
    fs.createReadStream(f).pipe(r);
  })
  .listen(3188, "127.0.0.1", () =>
    console.log("Isolated QA fixture preview 3188"),
  );
