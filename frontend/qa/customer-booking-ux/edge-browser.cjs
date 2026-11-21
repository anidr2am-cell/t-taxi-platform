"use strict";
const fs = require("node:fs"),
  path = require("node:path"),
  assert = require("node:assert/strict");
const root = path.resolve(__dirname, "../../.."),
  { chromium } = require(
    process.env.PLAYWRIGHT_MODULE ||
      path.join(root, "backend/node_modules/playwright"),
  );
const base = process.env.PREVIEW_URL,
  out = process.env.QA_OUTPUT,
  fixture = require("./booking-state.json");
if (
  !base?.startsWith("https://") ||
  new URL(base).hostname === "trider.taxi" ||
  !out
)
  throw Error("Isolated preview required");
(async () => {
  assert.equal(
    (await fetch(base)).headers.get("x-preview-backend"),
    "customer-booking-ux-20261121-fixture",
  );
  const b = await chromium.launch({ headless: true, channel: "chrome" }),
    results = [];
  const stored = (p) =>
    p.evaluate(() => {
      const raw = JSON.parse(
        localStorage.getItem("flutter.booking_wizard_draft_v2"),
      );
      return (typeof raw === "string" ? JSON.parse(raw) : raw).state;
    });
  async function load(p, state, url = "/booking?lang=en") {
    await p.goto(base + "/en/");
    await p.evaluate((state) => {
      localStorage.clear();
      sessionStorage.clear();
      localStorage.setItem("tride_analytics_consent", "denied");
      localStorage.setItem(
        "flutter.booking_wizard_draft_v2",
        JSON.stringify(
          JSON.stringify({
            version: 3,
            savedAt: new Date().toISOString(),
            expiresAt: new Date(Date.now() + 14400000).toISOString(),
            state,
          }),
        ),
      );
    }, state);
    await p.goto(base + url);
    await p.locator("flt-semantics-placeholder").dispatchEvent("click");
    await p.waitForFunction(() => /[1-5]\/5/.test(document.body.innerText));
    await p.waitForTimeout(600);
  }
  async function scenario(name, run) {
    const c = await b.newContext({ viewport: { width: 390, height: 900 } }),
      p = await c.newPage();
    try {
      await run(p, c);
      results.push({ name, ok: true });
      console.log("PASS", name);
    } catch (e) {
      results.push({ name, ok: false, error: e.message });
      await p
        .screenshot({ path: path.join(out, "FAILED-edge-" + name + ".png") })
        .catch(() => {});
      console.log("FAIL", name, e.message);
    } finally {
      await c.close();
    }
  }
  try {
    await scenario("landing-search-failure-and-empty", async (p, c) => {
      await p.goto(base + "/en/");
      await p.locator('[data-service="CITY_TRANSFER"]').click();
      await c.route("**/places/autocomplete?**", (r) =>
        r.fulfill({
          status: 503,
          contentType: "application/json",
          body: '{"success":false,"message":"QA RAW SECRET"}',
        }),
      );
      await p.fill("#quick-from", "QA");
      await p.waitForFunction(() =>
        document
          .querySelector("#quick-status")
          .textContent.includes("unavailable"),
      );
      const failed = await p.locator("#quick-status").innerText();
      assert(!failed.includes("QA RAW"));
      await p.screenshot({ path: path.join(out, "edge-place-failure.png") });
      await c.unroute("**/places/autocomplete?**");
      await c.route("**/places/autocomplete?**", (r) =>
        r.fulfill({
          status: 200,
          contentType: "application/json",
          body: '{"success":true,"data":{"predictions":[]}}',
        }),
      );
      await p.fill("#quick-from", "Empty");
      await p.waitForFunction(() =>
        document
          .querySelector("#quick-status")
          .textContent.includes("No places"),
      );
      assert.notEqual(await p.locator("#quick-status").innerText(), failed);
    });
    await scenario("flight-midnight-buffer", async (p) => {
      await load(p, {
        ...fixture,
        step: 0,
        flightNumber: "QA101",
        flightDate: "2026-12-10",
      });
      await p.getByRole("button", { name: "Look up", exact: true }).click();
      const buffer = p.getByRole("button").filter({ hasText: /50/ }).first();
      await buffer.waitFor();
      await buffer.click();
      await p.waitForTimeout(500);
      const s = await stored(p);
      assert.equal(s.pickupDate, "2026-12-11");
      assert.equal(s.pickupTime, "01:30");
      await p.screenshot({ path: path.join(out, "edge-flight-midnight.png") });
    });
    await scenario("flight-failure-still-allows-manual", async (p, c) => {
      await c.route("**/public/flights/search?**", (r) =>
        r.fulfill({
          status: 503,
          contentType: "application/json",
          body: '{"success":false,"message":"QA RAW FLIGHT FAILURE"}',
        }),
      );
      await load(p, {
        ...fixture,
        step: 0,
        flightNumber: "QA101",
        flightDate: "2026-12-10",
      });
      await p.getByRole("button", { name: "Look up", exact: true }).click();
      await p.waitForTimeout(700);
      assert(!(await p.locator("body").innerText()).includes("QA RAW"));
      assert(await p.getByRole("button").last().isEnabled());
      await p.getByRole("button").last().click();
      await p.waitForFunction(() => document.body.innerText.includes("2/5"));
      await p.screenshot({
        path: path.join(out, "edge-flight-manual-fallback.png"),
      });
    });
    for (const inquiry of [false, true])
      await scenario(
        inquiry ? "fare-inquiry" : "fare-failure",
        async (p, c) => {
          await c.route("**/bookings/pricing/calculate", (r) =>
            r.fulfill({
              status: inquiry ? 422 : 503,
              contentType: "application/json",
              body: JSON.stringify({
                success: false,
                error_code: inquiry
                  ? "PRICING_INQUIRY_REQUIRED"
                  : "SERVICE_UNAVAILABLE",
                message: "QA RAW FARE ERROR",
              }),
            }),
          );
          await load(p, { ...fixture, step: 2 });
          const text = await p.locator("body").innerText();
          assert(!text.includes("QA RAW"));
          assert(!text.includes("฿1,000"));
          assert(!(await p.getByRole("button").last().isEnabled()));
          await p.screenshot({
            path: path.join(
              out,
              inquiry ? "edge-fare-inquiry.png" : "edge-fare-failure.png",
            ),
          });
        },
      );
    await scenario("luggage-over-limit", async (p) => {
      await load(p, { ...fixture, step: 2, adults: 9 });
      const buttons = p
        .getByRole("button")
        .filter({ hasText: /^Select Vehicle/ });
      assert.equal(await buttons.count(), 3);
      for (const button of await buttons.all())
        assert(!(await button.isEnabled()));
      assert(!(await p.getByRole("button").last().isEnabled()));
      await p.screenshot({
        path: path.join(out, "edge-capacity-over-limit.png"),
      });
    });
    await scenario("option-requotes-selected-vehicle", async (p) => {
      await load(p, { ...fixture, step: 2 });
      const option = p.getByRole("button", { name: "Options", exact: true });
      await option.scrollIntoViewIfNeeded();
      await option.click();
      await p.waitForTimeout(350);
      let toggle = p.getByRole("switch", { name: /Name Sign/ });
      if (!(await toggle.count()))
        toggle = p.getByRole("checkbox", { name: /Name Sign/ });
      if (!(await toggle.count()))
        toggle = p.getByText("Name Sign Service (+100 THB)", { exact: true });
      const [quote] = await Promise.all([
        p.waitForResponse(
          (r) =>
            r.url().endsWith("/pricing/calculate") &&
            r.request().postDataJSON()?.options?.nameSign === true &&
            r.request().postDataJSON()?.vehicleTypeCode === "SEDAN",
        ),
        toggle.last().click(),
      ]);
      assert.equal((await quote.json()).data.totalAmount, 1100);
      await p.waitForTimeout(350);
      assert((await p.locator("body").innerText()).includes("฿1,100"));
      await p.screenshot({ path: path.join(out, "edge-option-requote.png") });
    });
    for (const code of ["DMK", "DROPOFF"])
      await scenario("route-" + code, async (p) => {
        const airport = {
          ...fixture.origin,
          id: "airport:DMK",
          code: "DMK",
          name: "DMK Airport",
          displayName: "DMK Airport",
          latitude: 13.91326,
          longitude: 100.60201,
        };
        await load(
          p,
          code === "DMK"
            ? { ...fixture, step: 0, origin: airport }
            : {
                ...fixture,
                step: 0,
                serviceType: "AIRPORT_DROPOFF",
                origin: fixture.destination,
                destination: fixture.origin,
              },
        );
        assert(
          (await p.locator("body").innerText()).includes(
            code === "DMK" ? "DMK Airport" : "QA Hotel",
          ),
        );
        assert(await p.getByRole("button").last().isEnabled());
        await p.screenshot({
          path: path.join(out, "edge-route-" + code + ".png"),
        });
      });
    await scenario("language-reload-and-fresh-customer", async (p) => {
      await load(p, { ...fixture, step: 3 });
      const previousHistory = await p.evaluate(() => history.state);
      await p.getByRole("button", { name: "Show menu", exact: true }).click();
      await p
        .getByRole("menuitem", { name: "日本語", exact: true })
        .last()
        .click();
      await p.waitForURL("**lang=ja");
      assert.deepEqual(await p.evaluate(() => history.state), previousHistory);
      assert.equal((await stored(p)).customerName, "QA Preview");
      await p.reload();
      await p.locator("flt-semantics-placeholder").dispatchEvent("click");
      await p.waitForFunction(() => document.body.innerText.includes("4/5"));
      assert.equal((await stored(p)).customerName, "QA Preview");
      await p.goto(base + "/en/");
      await p.locator("#quick-skip").click();
      await p.waitForURL("**/booking?**entry=**");
      await p.locator("flt-semantics-placeholder").dispatchEvent("click");
      await p.waitForFunction(() => document.body.innerText.includes("1/5"));
      assert.equal((await stored(p)).customerName, "");
    });
  } finally {
    await b.close();
    fs.writeFileSync(
      path.join(out, "edge-results.json"),
      JSON.stringify(results, null, 2),
    );
  }
  if (results.some((r) => !r.ok)) process.exitCode = 1;
})().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});
