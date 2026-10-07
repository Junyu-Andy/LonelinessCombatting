// Drives the T18 screenshot build (see t18_screens_main.dart).
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const BASE = process.env.SHOT_BASE || 'http://127.0.0.1:8718';
const OUT = __dirname;
async function btn(p, name) {
  for (let t = 0; t < 30; t++) {
    const box = await p.$$eval('flt-semantics[role="button"], flt-semantics',
      (ns, name) => {
        const n = ns.find((n) => n.textContent.trim() === name &&
          n.getAttribute('aria-disabled') !== 'true');
        if (!n) return null;
        const r = n.getBoundingClientRect();
        return [r.x + r.width / 2, r.y + r.height / 2];
      }, name);
    if (box) { await p.mouse.click(box[0], box[1]); await p.waitForTimeout(700); return; }
    await p.waitForTimeout(500);
  }
  throw new Error('button not found: ' + name);
}
async function open(browser, query) {
  const p = await browser.newPage({ viewport: { width: 412, height: 860 } });
  await p.goto(BASE + '/' + (query || ''));
  await p.waitForTimeout(6000);
  await p.evaluate(() => {
    const e = document.querySelector('flt-semantics-placeholder');
    if (e) e.click();
  });
  await p.waitForTimeout(1500);
  await btn(p, '打開問卷');
  await p.waitForTimeout(1500);
  return p;
}
(async () => {
  const browser = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium' });
  const p = await open(browser);
  await p.screenshot({ path: OUT + '/1_item1.png' });
  await btn(p, '是');
  await p.screenshot({ path: OUT + '/2_item2.png' });
  await btn(p, '上一題');
  await p.screenshot({ path: OUT + '/3_back_item1_selected.png' });
  await btn(p, '大致是');
  await btn(p, '跳過呢題');
  await btn(p, '不是');
  await p.screenshot({ path: OUT + '/4_item4_social.png' });
  await btn(p, '是'); await btn(p, '大致是'); await btn(p, '不是');
  await p.screenshot({ path: OUT + '/5_submit.png' });
  await p.close();
  const m = await open(browser, '?state=missed');
  await m.screenshot({ path: OUT + '/6_closed.png' });
  await browser.close();
})().catch((e) => { console.error(e); process.exit(1); });
