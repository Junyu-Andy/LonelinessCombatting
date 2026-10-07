// Captures every ADA / day-7 screen from the t17_screens_main.dart web build.
//   (cd build/web && python3 -m http.server 8717 --bind 127.0.0.1) &
//   node t17_shots.js
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const BASE = process.env.SHOT_BASE || 'http://127.0.0.1:8717';
const OUT = __dirname;
const SHOTS = [
  // Full form, 阿伯, voice off: all 12 screens.
  ...Array.from({ length: 12 }, (_, i) => [
    `ada_full_${String(i + 1).padStart(2, '0')}.png`,
    `page=ada&form=full&variant=masculine&screen=${i}` + (i === 11 ? '&text=1' : '')]),
  // Short form: Part A with 阿珍, and D (screen 7/7) voice off / on.
  ['ada_short_02_ahjan.png', 'page=ada&form=short&variant=feminine&screen=1'],
  ['ada_short_07_voice_off.png', 'page=ada&form=short&screen=6'],
  ['ada_short_07_voice_on.png', 'page=ada&form=short&screen=6&voice=1'],
  ['ada_skip_off.png', 'page=ada&form=short&screen=1&skip=0'],
  ['ada_done.png', 'page=ada&form=short&done=1'],
  ['day7_1.png', 'page=day7&screen=0'],
  ['day7_2.png', 'page=day7&screen=1'],
  ['day7_3_voice_on.png', 'page=day7&screen=2&voice=1'],
];
(async () => {
  // Local page direct; Flutter's fallback fonts via the proxy.
  const browser = await chromium.launch({ args: [
    `--proxy-server=${process.env.HTTPS_PROXY}`,
    '--proxy-bypass-list=127.0.0.1;localhost'] });
  for (const [file, query] of SHOTS) {
    const p = await browser.newPage({ viewport: { width: 412, height: 915 } });
    await p.goto(`${BASE}/?${query}`);
    await p.waitForTimeout(7000);
    await p.screenshot({ path: `${OUT}/${file}` });
    await p.close();
    console.log('shot', file);
  }
  await browser.close();
})();
