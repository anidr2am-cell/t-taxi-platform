"use strict";
const fs = require("node:fs"),
  path = require("node:path"),
  assert = require("node:assert/strict");
const root = path.resolve(__dirname, "../../..");
const { chromium } = require(
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
  throw Error("Isolated HTTPS preview and output required");
(async () => {
  assert.equal(
    (await fetch(base)).headers.get("x-preview-backend"),
    "customer-booking-ux-20261121-fixture",
  );
  const b = await chromium.launch({ headless: true, channel: "chrome" }),
    results = [];
  const queue = ["ko", "en", "th", "ja", "zh", "ru", "zh-TW"].flatMap((lang) =>
    [360, 390, 768, 1280].map((width) => ({ lang, width })),
  );
  async function worker() {
    while (queue.length) {
      const { lang, width } = queue.shift(),
        c = await b.newContext({
          viewport: { width, height: 900 },
          permissions: ["clipboard-read", "clipboard-write"],
        }),
        p = await c.newPage();
      let posts = 0;
      const keys = [];
      const lostResponse = lang === "ko" && width === 390;
      try {
        await c.route("**/*", async (r) => {
          const q = r.request(),
            u = new URL(q.url());
          if (
            u.origin !== new URL(base).origin &&
            !["GET", "HEAD"].includes(q.method())
          )
            return r.abort();
          if (
            ["lin.ee", "line.me", "wa.me", "t.me", "open.kakao.com"].includes(
              u.hostname,
            )
          ) {
            assert(!q.url().includes("qa-preview-only"));
            return r.fulfill({
              status: 200,
              body: "QA: no external messenger connection or message is sent",
            });
          }
          if (q.method() === "POST" && u.pathname === "/api/v1/bookings") {
            posts++;
            keys.push(q.headers()["idempotency-key"]);
            if (lostResponse && posts === 1) {
              const accepted = await r.fetch();
              assert.equal(accepted.status(), 200);
              return r.fulfill({
                status: 503,
                contentType: "application/json",
                body: JSON.stringify({
                  success: false,
                  message: "QA raw upstream response must not be displayed",
                }),
              });
            }
          }
          return r.continue();
        });
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
                state: { ...state, step: 4 },
              }),
            ),
          );
        }, fixture);
        await p.goto(base + "/booking?lang=" + lang);
        await p.locator("flt-semantics-placeholder").dispatchEvent("click");
        await p.waitForFunction(() => document.body.innerText.includes("5/5"));
        await p.waitForTimeout(700);
        if (lostResponse) {
          const failed = p.waitForResponse(
            (r) =>
              new URL(r.url()).pathname === "/api/v1/bookings" &&
              r.status() === 503,
          );
          await p.getByRole("button").last().click();
          await failed;
          await p.waitForTimeout(700);
          assert(
            !(await p.locator("body").innerText()).includes(
              "QA raw upstream response",
            ),
          );
        }
        const created = p.waitForResponse(
          (r) =>
            new URL(r.url()).pathname === "/api/v1/bookings" &&
            r.status() === 200,
        );
        await p.getByRole("button").last().dblclick({ delay: 10 });
        const row = (await (await created).json()).data;
        assert(row.bookingNumber.startsWith("QA-PREVIEW-"));
        assert.equal(posts, lostResponse ? 2 : 1);
        if (lostResponse) assert.equal(keys[0], keys[1]);
        const line = p.getByRole("button").filter({ hasText: /LINE/ }).last();
        await line.waitFor();
        const started = p.waitForResponse(
          (r) =>
            r.url().endsWith("/contact-connections") &&
            r.request().method() === "POST",
        );
        await line.click();
        await started;
        await p.waitForTimeout(450);
        const connection = () =>
          fetch(
            base +
              "/api/v1/bookings/" +
              row.bookingNumber +
              "/contact-connection",
          ).then((r) => r.json());
        assert.equal((await connection()).data.contactStatus, "PENDING");
        const sent = p.waitForResponse((r) =>
          r.url().endsWith("/contact-connections/confirm-sent"),
        );
        await p.getByRole("button").last().click();
        await sent;
        await p.waitForFunction(() =>
          document.body.innerText.includes("฿1,000"),
        );
        await p.waitForTimeout(450);
        assert.equal(
          (await connection()).data.contactStatus,
          "CONFIRM_REQUESTED",
        );
        let text = await p.locator("body").innerText();
        assert(!/\bSEDAN\b|undefined|NaN|QA raw upstream/.test(text));
        if (lang === "zh-TW") assert(!/机场|预约|选择/.test(text));
        await p.screenshot({
          path: path.join(out, `${lang}-${width}-complete.png`),
        });
        await p.mouse.move(width / 2, 500);
        await p.mouse.wheel(0, 750);
        await p.waitForTimeout(300);
        await p.screenshot({
          path: path.join(out, `${lang}-${width}-meeting.png`),
        });
        results.push({
          lang,
          width,
          ok: true,
          syntheticBooking: row.bookingNumber,
          createRequests: posts,
          responseLossRetrySameKey: lostResponse || undefined,
          openDidNotVerify: true,
          selfReportedStatus: "CONFIRM_REQUESTED",
          externalMessagesSent: 0,
        });
        console.log("PASS completion", lang, width);
      } catch (e) {
        results.push({ lang, width, ok: false, error: e.message });
        await p
          .screenshot({
            path: path.join(out, `FAILED-complete-${lang}-${width}.png`),
          })
          .catch(() => {});
        console.log("FAIL completion", lang, width, e.message);
      } finally {
        await c.close();
      }
    }
  }
  try {
    await Promise.all([worker(), worker()]);
  } finally {
    await b.close();
    fs.writeFileSync(
      path.join(out, "completion-results.json"),
      JSON.stringify(results, null, 2),
    );
  }
  if (results.some((x) => !x.ok)) process.exitCode = 1;
})().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});
