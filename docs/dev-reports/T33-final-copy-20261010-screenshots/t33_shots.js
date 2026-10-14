// T33 screenshots: Arm B check-in (five moods) and reminiscence (five
// moods, no mood, grief) and the onboarding S5 screen.  Serve the web build on BASE first, e.g.
//   npx http-server build/web -p 8733
// Writes raw_*.png; the three sheets in this folder were stitched from
// them with PIL (5 check-in moods; 5 reminiscence moods; no mood + grief)
// and the raw files deleted; 4_onboarding_S5.png is written directly.  The web build needs a local, uncommitted
// one-line patch to SafetyService.newTurnId (see the T33 report).
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const BASE = process.env.BASE || 'http://127.0.0.1:8733';
const OUT = __dirname;
async function open(browser, page, h) {
  const p = await browser.newPage({ viewport: { width: 412, height: h } });
  await p.goto(BASE + '/?page=' + page);
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
const FACES = ['好好', '幾好', '麻麻地', '差', '好差']; // rank 5 … 1
async function checkIn(browser, face, file) {
  const p = await open(browser, 'checkin_b', 1500);
  await btn(p, face); await btn(p, '少少'); await btn(p, '麻麻'); await btn(p, '一啲小事');
  await type(p, '今日去咗飲茶');
  await p.mouse.click(10, 10);
  await btn(p, '儲存今日 Check-in'); await p.waitForTimeout(2500);
  await p.screenshot({ path: OUT + '/' + file }); await p.close();
}
async function remi(browser, text, face, file) {
  const p = await open(browser, 'remi_b', 1000);
  await type(p, text);
  await p.mouse.click(10, 10);
  if (face) await btn(p, face);
  await btn(p, '儲存呢段回憶'); await p.waitForTimeout(2500);
  await p.screenshot({ path: OUT + '/' + file }); await p.close();
}
(async () => {
  const browser = await chromium.launch();
  for (let i = 0; i < 5; i++) await checkIn(browser, FACES[i], `raw_checkin_${5 - i}.png`);
  for (let i = 0; i < 5; i++) await remi(browser, '細個住喺深水埗，成日喺樓下玩。', FACES[i], `raw_remi_${5 - i}.png`);
  await remi(browser, '細個住喺深水埗，成日喺樓下玩。', null, 'raw_remi_none.png');
  await remi(browser, '老伴走咗之後，我成日諗起佢。', '好好', 'raw_remi_grief.png');
  // Onboarding with the S5 switch on: walk to the last screen.
  const p = await open(browser, 'onboarding_s5', 915);
  await btn(p, '下一步'); await btn(p, '下一步');
  await btn(p, '阿珍（同輩女性）'); await btn(p, '下一步'); await btn(p, '下一步');
  await p.waitForTimeout(1000);
  await p.screenshot({ path: OUT + '/4_onboarding_S5.png' }); await p.close();
  await browser.close();
})().catch(e => { console.error(e); process.exit(1); });
