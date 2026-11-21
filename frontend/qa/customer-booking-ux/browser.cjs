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
  output =
    process.env.QA_OUTPUT ||
    path.join(root, "frontend/qa/screenshots/customer-booking-ux");
if (
  !base ||
  !base.startsWith("https://") ||
  new URL(base).hostname === "trider.taxi"
)
  throw Error("An isolated HTTPS preview is required");
fs.mkdirSync(output, { recursive: true });
const fixture = require("./booking-state.json"),
  results = [];
const languages = (process.env.QA_LANGUAGES || "ko,en,th,ja,zh,ru,zh-TW").split(
    ",",
  ),
  widths = [360, 390, 768, 1280];
async function semantics(p) {
  const toggle = p.locator("flt-semantics-placeholder");
  await toggle.waitFor({ state: "attached", timeout: 30000 }).catch(() => {});
  if (await toggle.count()) await toggle.dispatchEvent("click");
  await p.waitForFunction(
    () => /[1-5]\/5/.test(document.body.innerText),
    {},
    { timeout: 30000 },
  );
  await p.waitForTimeout(550);
}
(async () => {
  const b = await chromium.launch({
    headless: true,
    channel: process.env.QA_BROWSER_CHANNEL || "chrome",
  });
  const queue = languages.flatMap((lang) =>
    widths.map((width) => ({ lang, width })),
  );
  async function worker() {
    while (queue.length) {
      const { lang, width } = queue.shift();
      const c = await b.newContext({ viewport: { width, height: 900 } });
      const p = await c.newPage();
      const failures = [];
      p.on("pageerror", (e) => failures.push(e.message));
      await c.route("**/*", (route) => {
        const req = route.request();
        if (
          !["GET", "HEAD"].includes(req.method()) &&
          new URL(req.url()).origin !== new URL(base).origin
        )
          return route.abort();
        return route.continue();
      });
      try {
        for (let step = 0; step < 5; step++) {
          await p.goto(base + "/en/", { waitUntil: "domcontentloaded" });
          const state = { ...fixture, step };
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
          await p.goto(base + "/booking?lang=" + lang, {
            waitUntil: "domcontentloaded",
          });
          await semantics(p);
          let text = await p.locator("body").innerText();
          assert(
            text.includes(`${step + 1}/5`),
            `${lang}/${width} step ${step + 1}`,
          );
          assert(
            !/undefined|NaN|Exception:|Google Places provider is not configured/.test(
              text,
            ),
          );
          if (lang === "zh-TW")
            assert(!/机场|预约|选择/.test(text), "Simplified Chinese leaked");
          await p.screenshot({
            path: path.join(output, `${lang}-${width}-step${step + 1}.png`),
          });
          if (step === 2) {
            await p.mouse.move(width / 2, 500);
            await p.mouse.wheel(0, 650);
            await p.waitForTimeout(350);
            await p.screenshot({
              path: path.join(output, `${lang}-${width}-vehicles.png`),
            });
            await p.mouse.wheel(0, 650);
            await p.waitForTimeout(350);
            await p.screenshot({
              path: path.join(output, `${lang}-${width}-fare.png`),
            });
          }
        }
        results.push({
          lang,
          width,
          steps: 5,
          uncaughtErrors: failures,
          ok: failures.length === 0,
        });
        console.log(`PASS ${lang} ${width}: five steps`);
      } catch (e) {
        await p
          .screenshot({
            path: path.join(output, `FAILED-${lang}-${width}.png`),
          })
          .catch(() => {});
        results.push({
          lang,
          width,
          ok: false,
          error: e.message,
          uncaughtErrors: failures,
        });
        console.log(`FAIL ${lang} ${width}: ${e.message}`);
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
      path.join(
        output,
        process.env.QA_LANGUAGES
          ? "browser-results-" + process.env.QA_LANGUAGES + ".json"
          : "browser-results.json",
      ),
      JSON.stringify(
        { browser: "Chrome headless", realPhonesTested: false, results },
        null,
        2,
      ),
    );
  }
  if (results.some((x) => !x.ok)) process.exitCode = 1;
})().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});
