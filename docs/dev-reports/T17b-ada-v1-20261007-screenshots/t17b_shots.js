// Captures the T17b screens from the t17b_screens_main.dart web build.
//   (cd build/web && python3 -m http.server 8717 --bind 127.0.0.1) &
//   node t17b_shots.js
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const BASE = process.env.SHOT_BASE || 'http://127.0.0.1:8717';
const OUT = __dirname;
const pad = (i) => String(i + 1).padStart(2, '0');
const SHOTS = [
  // Short form (visit 1: B + D + reminder time), 阿珍, voice off.
  ...Array.from({ length: 7 }, (_, i) => [`short_${pad(i)}_ahjan.png`,
    `page=ada&form=short&variant=feminine&screen=${i}`]),
  ['short_06_voice_on.png', 'page=ada&form=short&variant=feminine&screen=5&voice=1'],
  // Full form (day 7: A + B + C + D), 阿伯, voice off.
  ...Array.from({ length: 12 }, (_, i) => [`full_${pad(i)}_ahbak.png`,
    `page=ada&form=full&variant=masculine&screen=${i}` + (i === 11 ? '&text=1' : '')]),
  ['full_12_voice_on.png', 'page=ada&form=full&variant=masculine&screen=11&voice=1'],
  ['full_02_ahjan.png', 'page=ada&form=full&variant=feminine&screen=1'],
  // Skipped items show 已跳過.
  ['skip_b1.png', 'page=ada&form=full&variant=masculine&screen=2&skipped=1'],
  ['skip_c3.png', 'page=ada&form=full&variant=masculine&screen=8&skipped=1'],
  // Day-7 flow: fresh intro; stopped half-way; resumed in part 1; part 2.
  ['flow_intro.png', 'page=flow'],
  ['flow_resume_hub.png', 'page=flow&state=partial'],
  ['flow_resume_part1.png', 'page=ada&form=full&variant=masculine&screen=5&part=1'],
  ['flow_part2_open.png', 'page=day7&screen=0'],
  // Reminder push (mock) and the home card.
  ['push_mock.png', 'page=push'],
  ['home_card.png', 'page=home'],
  // Researcher page.
  ['staff_status.png', 'page=staff'],
];
(async () => {
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
