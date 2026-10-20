#!/usr/bin/env node
/**
 * 1021 小讀本 — step 2 of tool/readers_shots_1021.sh: render the pages the
 * App would load (written by test_manual/readers_shots_1021_test.dart, step
 * 1) in headless Chromium, and check every unit.
 *
 *   NODE_PATH="$(npm root -g)" node tool/render_reader_shots.js \
 *     build/readers_shots_1021/jobs.json
 *
 * Each page is the App's prepared HTML (CSP, data-chrome="app", data-ask
 * for Hybrid, --fs 1.30, setRead, the App's page script), opened with
 * setContent — no base URL, network off, every request refused — in a
 * viewport the size of the WebView area under the native top bar.  A stub
 * window.PeizhuReader (the App's JavaScript channel) is added right after
 * the CSP and takes what the App's page script posts.
 *
 * Picture jobs: one PNG of the visible screen (the contents; one section,
 * opened by tapping it in the contents; the finished contents).
 * Check jobs (every unit, both arms): at that width and --fs, the contents
 * and every section must not scroll sideways; tapping each section must
 * post peizhu:view for it; peizhuReader.back() must return true from a
 * section and false from the contents; readIds() must list the sections
 * left; every peizhu://explain button must be hidden, every other
 * peizhu:// link must be a CTA or a packaged unit; no request may leave
 * the page; no script error.  Exit 1 if any check fails.
 *
 * Needs Playwright (preinstalled globally here; NODE_PATH as above) and
 * Chromium: CHROMIUM_PATH, else /opt/pw-browsers/chromium if present,
 * else Playwright's own.  Writes only the PNGs named in jobs.json.
 */
"use strict";

const fs = require("fs");
const path = require("path");

let chromium;
try {
  chromium = require("playwright").chromium;
} catch (e) {
  console.error("需要 Playwright：NODE_PATH=\"$(npm root -g)\" node tool/render_reader_shots.js …");
  process.exit(1);
}

const CTA = ["small_action", "plan", "thought", "chat_siu_yan"];

function executablePath() {
  if (process.env.CHROMIUM_PATH) return process.env.CHROMIUM_PATH;
  if (fs.existsSync("/opt/pw-browsers/chromium")) return "/opt/pw-browsers/chromium";
  return undefined;
}

async function openPage(browser, job) {
  const context = await browser.newContext({
    viewport: {width: Math.round(job.width), height: Math.round(job.height)},
    deviceScaleFactor: job.dpr || 1,
    offline: true,
    javaScriptEnabled: true,
  });
  const requests = [];
  await context.route("**/*", (route) => {
    requests.push(route.request().url());
    return route.abort();
  });
  const page = await context.newPage();
  const errors = [];
  page.on("pageerror", (e) => errors.push(String(e)));
  // The stub channel goes in as the first script after the App's CSP (an
  // init script does not survive setContent's document.write).
  const html = fs.readFileSync(job.html, "utf8").replace(
      /(<meta http-equiv="Content-Security-Policy"[^>]*>)/,
      "$1<script>window.__posted=[];window.PeizhuReader={postMessage:" +
      "function(m){window.__posted.push(String(m));}};</script>");
  await page.setContent(html, {waitUntil: "load"});
  await page.waitForTimeout(150);
  return {context, page, requests, errors};
}

const posted = (page) => page.evaluate(() => window.__posted.slice());

async function overflow(page) {
  return page.evaluate(() => {
    const d = document.documentElement;
    return d.scrollWidth - d.clientWidth;
  });
}

async function picture(browser, job) {
  const {context, page, requests, errors} = await openPage(browser, job);
  if (job.section) {
    await page.click(`.toc-item[data-go="${job.section}"]`);
    await page.waitForTimeout(150);
  }
  await page.screenshot({path: job.png});
  const out = {name: job.name, png: job.png, requests: requests.length, errors};
  await context.close();
  return out;
}

async function check(browser, job) {
  const problems = [];
  const {context, page, requests, errors} = await openPage(browser, job);
  const say = (m) => problems.push(m);

  const chrome = await page.evaluate(() => [
    document.documentElement.getAttribute("data-chrome"),
    document.documentElement.getAttribute("data-ask"),
    document.documentElement.getAttribute("data-explain"),
    getComputedStyle(document.documentElement).getPropertyValue("--fs").trim(),
  ]);
  if (chrome[0] !== "app") say(`data-chrome = ${chrome[0]}`);
  if ((chrome[1] === "on") !== (job.arm === "hybrid")) say(`data-ask = ${chrome[1]} (${job.arm})`);
  if (chrome[2] !== null) say(`data-explain = ${chrome[2]}`);
  if (chrome[3] !== "1.30") say(`--fs = ${chrome[3]}`);

  // The page's own top bar is hidden; the 「?」 explain buttons too.
  const hidden = await page.evaluate(() => {
    const vis = (el) => el.getClientRects().length > 0 &&
        getComputedStyle(el).display !== "none" && getComputedStyle(el).visibility !== "hidden";
    const bars = Array.prototype.filter.call(document.querySelectorAll(".sec-bar"), vis).length;
    const asks = document.querySelectorAll('a[href^="peizhu://explain"]');
    let shown = 0;
    asks.forEach((a) => {
      if (getComputedStyle(a).display !== "none") shown++;
    });
    const links = Array.prototype.map.call(document.querySelectorAll('a[href^="peizhu://"]'),
        (a) => a.getAttribute("href"));
    return {bars, asks: asks.length, shown, links};
  });
  if (hidden.shown) say(`${hidden.shown} 个 peizhu://explain 按钮看得到`);
  for (const href of hidden.links) {
    let m = /^peizhu:\/\/cta\/([a-z_]+)$/.exec(href);
    if (m) {
      if (CTA.indexOf(m[1]) < 0) say(`不认识的 ${href}`);
      continue;
    }
    m = /^peizhu:\/\/reader\/open\?id=([a-z0-9_-]+)$/.exec(href);
    if (m) {
      if (job.units.indexOf(m[1]) < 0) say(`${href} 指向没有打包的单元`);
      continue;
    }
    if (/^peizhu:\/\/explain\?card=/.test(href)) continue;
    say(`不认识的 ${href}`);
  }

  let o = await overflow(page);
  if (o > 1) say(`目录横向超出 ${o}px`);
  const first = await posted(page);
  const firstView = first.filter((m) => m.charAt(0) === "{").map((m) => JSON.parse(m));
  if (!firstView.length || firstView[0].view !== "toc") say("开头没有收到目录的 peizhu:view");

  const left = [];
  for (let i = 0; i < job.sections.length; i++) {
    const s = job.sections[i];
    const before = (await posted(page)).length;
    await page.click(`.toc-item[data-go="${s}"]`);
    await page.waitForTimeout(80);
    const msgs = (await posted(page)).slice(before);
    const view = msgs.filter((m) => m.charAt(0) === "{").map((m) => JSON.parse(m));
    if (!view.length || view[view.length - 1].view !== s) say(`撳 ${s} 没有收到 peizhu:view`);
    else if (view[view.length - 1].index !== i + 1 || view[view.length - 1].total !== job.sections.length) {
      say(`${s} 的 index/total 不对：${JSON.stringify(view[view.length - 1])}`);
    }
    if (msgs.indexOf(s) < 0) say(`${s} 没有报 reader_section`);
    o = await overflow(page);
    if (o > 1) say(`${s} 横向超出 ${o}px`);
    const back = await page.evaluate(() => window.peizhuReader.back());
    if (back !== true) say(`在 ${s} 时 back() = ${back}`);
    left.push(s);
    const ids = await page.evaluate(() => window.peizhuReader.readIds());
    for (const l of left) if (ids.indexOf(l) < 0) say(`readIds() 没有 ${l}`);
  }
  const atToc = await page.evaluate(() => window.peizhuReader.back());
  if (atToc !== false) say(`在目录时 back() = ${atToc}`);
  const done = await page.evaluate(() => {
    const box = document.querySelector("[data-done-box]");
    return box ? !box.hidden : null;
  });
  if (done === false) say("三节读完后目录没有显示「睇完」一块");
  if (requests.length) say(`有请求想出去：${requests.slice(0, 3).join("、")}`);
  if (errors.length) say(`脚本错误：${errors.slice(0, 2).join("；")}`);
  await context.close();
  return {name: job.name, unit: job.unit, arm: job.arm, problems, links: hidden.links.length,
    explain: hidden.asks};
}

async function main() {
  const jobsPath = process.argv[2] || "build/readers_shots_1021/jobs.json";
  const jobs = JSON.parse(fs.readFileSync(jobsPath, "utf8"));
  const browser = await chromium.launch({executablePath: executablePath()});
  let failed = 0;
  try {
    for (const job of jobs.filter((j) => !j.check)) {
      const r = await picture(browser, job);
      console.log(`图：${path.basename(r.png)}  ${job.width}×${job.height}` +
          (r.requests ? `  请求被拦 ${r.requests} 个` : "") +
          (r.errors.length ? `  脚本错误 ${r.errors.join("；")}` : ""));
      if (r.errors.length) failed++;
    }
    for (const job of jobs.filter((j) => j.check)) {
      const r = await check(browser, job);
      if (r.problems.length) {
        failed++;
        console.log(`不通过  ${r.arm} ${r.unit}`);
        for (const p of r.problems) console.log(`        ${p}`);
      } else {
        console.log(`通过    ${r.arm} ${r.unit}（peizhu:// 链接 ${r.links} 个，其中 explain ${r.explain} 个都看不到）`);
      }
    }
  } finally {
    await browser.close();
  }
  if (failed) {
    console.log(`Chromium 检查：${failed} 项不通过`);
    process.exit(1);
  }
  console.log("Chromium 检查：全部通过");
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
