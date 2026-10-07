const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const IP = process.env.SHOT_HOST || '192.0.2.2', OUT = '/home/user/LonelinessCombatting/docs/dev-reports/T15-rule-based-replies-20261007-screenshots';
const OFF = 'http://'+IP+':8701', ON = 'http://'+IP+':8702';
async function open(browser, base, page, h) {
  const p = await browser.newPage({ viewport: { width: 412, height: h } });
  await p.goto(base + '/?page=' + page);
  await p.waitForTimeout(6000);
  return p;
}
async function btn(p, name) {
  for (let t = 0; t < 20; t++) {
    const box = await p.$$eval('flt-semantics[role="button"]', (ns, name) => {
      const n = ns.find(n => n.textContent.trim().split('\n').pop().trim() === name && n.getAttribute('aria-disabled') !== 'true');
      if (!n) return null; const r = n.getBoundingClientRect(); return [r.x + r.width / 2, r.y + r.height / 2];
    }, name);
    if (box) { await p.mouse.click(box[0], box[1]); await p.waitForTimeout(400); return; }
    await p.waitForTimeout(500);
  }
  throw new Error('button not found: ' + name);
}
async function type(p, text) {
  const f = p.locator('textarea, input').first();
  await f.click(); await p.waitForTimeout(300);
  await p.keyboard.insertText(text); await p.waitForTimeout(500);
}
async function checkInB(browser, base, file) {
  const p = await open(browser, base, 'checkin_b', 1420);
  await btn(p, '好差'); await btn(p, '少少'); await btn(p, '麻麻'); await btn(p, '一啲小事');
  await type(p, '今日去咗飲茶');
  await p.mouse.click(10, 10);
  await btn(p, '儲存今日 Check-in'); await p.waitForTimeout(2500);
  await p.screenshot({ path: OUT + '/' + file }); await p.close();
}
async function remiB(browser, base, before, after) {
  const p = await open(browser, base, 'remi_b', 915);
  await type(p, '細個住喺深水埗，成日喺樓下玩。');
  await p.mouse.click(10, 10);
  if (base === ON) await btn(p, '幾好');
  await p.waitForTimeout(500);
  await p.screenshot({ path: OUT + '/' + before });
  if (after) { await btn(p, '儲存呢段回憶'); await p.waitForTimeout(2500); await p.screenshot({ path: OUT + '/' + after }); }
  await p.close();
}
(async () => {
  const proxy = process.env.HTTPS_PROXY;
  const browser = await chromium.launch({ proxy: { server: proxy, bypass: IP } });
  await checkInB(browser, OFF, 'checkin_b_off.png');
  await checkInB(browser, ON, 'checkin_b_on.png');
  await remiB(browser, OFF, 'remi_b_off.png', null);
  await remiB(browser, ON, 'remi_b_on_before.png', 'remi_b_on_after.png');
  // Hybrid check-in: mood gate, then one message.
  let p = await open(browser, OFF, 'checkin_a', 915);
  await btn(p, '好差'); await btn(p, '開始傾偈'); await p.waitForTimeout(2000);
  await type(p, '今日去咗飲茶');
  await p.keyboard.press('Enter'); await p.waitForTimeout(500);
  await p.screenshot({ path: OUT + '/checkin_a_hybrid.png' }); await p.close();
  p = await open(browser, OFF, 'remi_a', 915);
  await p.waitForTimeout(2000);
  await p.screenshot({ path: OUT + '/remi_a_hybrid.png' }); await p.close();
  await browser.close();
})().catch(e => { console.error(e); process.exit(1); });
