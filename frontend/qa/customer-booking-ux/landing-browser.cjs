"use strict";
const fs = require("node:fs"),
  path = require("node:path"),
  assert = require("node:assert/strict"),
  root = path.resolve(__dirname, "../../..");
const { chromium } = require(
  process.env.PLAYWRIGHT_MODULE ||
    path.join(root, "backend/node_modules/playwright"),
);
const base = process.env.PREVIEW_URL,
  out = process.env.QA_OUTPUT;
if (
  !base?.startsWith("https://") ||
  new URL(base).hostname === "trider.taxi" ||
  !out
)
  throw Error("Isolated HTTPS preview and QA_OUTPUT required");
(async () => {
  assert.equal(
    (await fetch(base)).headers.get("x-preview-backend"),
    "customer-booking-ux-20261121-fixture",
  );
  fs.mkdirSync(out, { recursive: true });
  const b = await chromium.launch({ headless: true, channel: "chrome" }),
    checks = [];
  try {
    for (const lang of ["ko", "en", "th", "ja", "zh", "zh-TW"])
      for (const width of [360, 390, 768, 1280]) {
        const c = await b.newContext({ viewport: { width, height: 900 } }),
          p = await c.newPage();
        await c.addInitScript(() =>
          localStorage.setItem("tride_analytics_consent", "denied"),
        );
        await p.goto(base + (lang === "ko" ? "/" : `/${lang}/`));
        await p.locator("#fleet").scrollIntoViewIfNeeded();
        await p
          .locator("#fleet img")
          .evaluateAll((imgs) => Promise.all(imgs.map((img) => img.decode())));
        await p.evaluate(() => scrollTo(0, 0));
        assert(
          !(await p.evaluate(
            () => document.documentElement.scrollWidth > innerWidth,
          )),
          `${lang}/${width} overflow`,
        );
        assert(!/undefined|NaN/.test(await p.locator("body").innerText()));
        await p.screenshot({
          path: path.join(out, `home-${lang}-${width}.png`),
          fullPage: true,
        });
        checks.push({ lang, width, ok: true });
        await c.close();
      }
    const c = await b.newContext(),
      p = await c.newPage();
    await p.goto(base + "/en/");
    await p.selectOption("#airport-from", "BKK");
    await p.fill("#quick-to", "QA");
    await p.getByRole("button", { name: "QA Hotel" }).click();
    await p.waitForFunction(
      () => document.querySelector("#quick-to").value === "QA Hotel",
    );
    await p.selectOption("#language-select", "zh-TW");
    await p.waitForURL("**/zh-TW/");
    assert.equal(await p.inputValue("#airport-from"), "BKK");
    assert.equal(await p.inputValue("#quick-to"), "QA Hotel");
    await p.locator(".primary-action").click();
    await p.waitForURL("**/booking?**");
    const url = new URL(p.url());
    assert.equal(url.searchParams.get("lang"), "zh-TW");
    assert(!url.search.includes("QA Hotel"));
    await p.locator("flt-semantics-placeholder").dispatchEvent("click");
    await p.waitForFunction(() => document.body.innerText.includes("QA Hotel"));
    checks.push({ landingLanguageAndRouteRetained: true });
    await c.close();
    fs.writeFileSync(
      path.join(out, "landing-results.json"),
      JSON.stringify(checks, null, 2),
    );
    console.log(
      "PASS 24 landing views; language switch and route handoff into the built app",
    );
  } finally {
    await b.close();
  }
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
