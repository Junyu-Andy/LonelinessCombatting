#!/usr/bin/env node
/**
 * tool/check_prelaunch_values.js — READ-ONLY.  Prints the current value of
 * every switch and config document the 10/19 launch depends on (10/21
 * values per dev-tasks-1020 §3 where it changed them), next to
 * the value the checklist expects, so Junyu can run it once and paste the
 * result (dev-tasks-1018 §G4).  Writes nothing.  Never prints an arm, a
 * sequence or a full e-mail address.
 *
 * Emulator (default):
 *   NODE_PATH=functions/node_modules node tool/check_prelaunch_values.js
 * Real project (needs a service account in GOOGLE_APPLICATION_CREDENTIALS):
 *   NODE_PATH=functions/node_modules node tool/check_prelaunch_values.js \
 *     --project=loneliness-pilot-dev --production-confirm=loneliness-pilot-dev
 *
 * Expected values: docs/release/firestore-config-checklist-1015.md and
 * dev-tasks-1018 §G / §E1.  "—" = no expectation, shown for information.
 */
'use strict';

const {parseArgs, checkTarget} = require('./firestore_target');

/** [doc, key, expected, note].  expected: true/false/number/string/null. */
const CHECKS = [
  ['app_config/feature_flags', 'onboardingAfterEnrollmentFix', true,
    'T37 登记后先走引导'],
  // dev-tasks-1020 §3: the 10/21 values.
  ['app_config/feature_flags', 'voiceInputEnabled', false,
    'T58 语音输入隐藏（10/21 关）'],
  ['app_config/feature_flags', 'transcriptRetentionToggleEnabled', false,
    'T51 不显示「保留對話紀錄」'],
  // dev-tasks-1020 §3, batch 4 (also batch 2's switch for the App).
  ['app_config/feature_flags', 'checkInChatV2Enabled', true,
    'T55 check-in 对话化 + 08:30 P1、19:00 P2（10/21 开）'],
  ['app_config/feature_flags', 'weeklyReminderV2Enabled', true,
    'T56 每周问卷整日窗口、10:00 提醒、给 Junyu 的电邮（1020e；装新构建后开）'],
  // 1020b §2: two of #126's switches stay off for 10/21; 1020c 一: Junyu
  // turns the other two on once the 10/20 phone test passes, before the
  // first RCT- registration.
  ['app_config/feature_flags', 'homeMoodOpensCheckInEnabled', 'off',
    '#126，被第 3 批 E 节取代'],
  ['app_config/feature_flags', 'briefPrHomeBannerEnabled', 'off',
    '#126，被第 3 批 D 节取代'],
  ['app_config/feature_flags', 'appFontScaleOnlyEnabled', true,
    '#126，1020c 定开（10/20 手机测试过后、第一位 RCT- 前）'],
  // 1020l §二 (2): iPad only (phones never change); expected value set by
  // Junyu.
  ['app_config/feature_flags', 'wideScreenFrameEnabled', null,
    '1020l iPad 等大屏内容限宽 600、居中（手机不变，两组相同），期望值待 Junyu 定'],
  ['app_config/feature_flags', 'suggestionsUseProfileEnabled', true,
    '#126，1020c 定开（同上）'],
  ['app_config/feature_flags', 'usageEventsEnabled', true, 'T40 使用事件'],
  ['app_config/feature_flags', 'opsDashboardEnabled', true, 'T39 运营看板'],
  ['app_config/feature_flags', 'enrollmentGateEnabled', true,
    'T21 登记门（10/19 登记前开）'],
  ['app_config/feature_flags', 'researcherIntakeEnabled', true,
    'T47 研究员录入（合并部署后开）'],
  ['app_config/feature_flags', 'memoryLayersNoticeEnabled', true,
    'T31 S7 说明，和 layersEnabled 一起开（10/19）'],
  ['app_config/feature_flags', 'testerArmSwitchEnabled', null,
    '测试员切组（PR #112，合了才有）'],
  // 1020f 第三节: switches added by 1020d / 1020e.  Junyu sets the
  // expected values on the evening of 10/20 (until then "—", shown only).
  // The 1020f 第一节 fixes (measure wording) have no switch.
  ['app_config/feature_flags', 'safetyFalseAlarmMarkEnabled', null,
    '1020e 二.9「誤觸」标记（#128），期望值 10/20 晚定'],
  ['app_config/feature_flags', 'actionPlanSimplifiedEnabled', null,
    '1020e 二.7 (1) 行动计划少填、可改可删（#135），期望值 10/20 晚定'],
  ['app_config/feature_flags', 'actionPlanMemoryEnabled', null,
    '1020e 二.7 (2) 计划接上小欣记忆（#135），期望值 10/20 晚定'],
  ['app_config/feature_flags', 'researcherIntakeGateEnabled', true,
    '1020e 二.14 研究员讲解闸门（#136），10/20 第 54 条定开'],
  ['app_config/feature_flags', 'reminiscenceV2Enabled', null,
    '1020d 回忆 v2（#137），期望值 10/20 晚定'],
  ['app_config/feature_flags', 'leaveButtonV2Enabled', null,
    '1020d 离开按钮（#137），期望值 10/20 晚定'],
  // 1020g 一 (3): switches the 10/20 review found missing.  Expected
  // values are set by Junyu at the freeze (10/20 item 56 (3)); "—" until
  // then.  homeLayoutV2Enabled and moodRowV2Enabled must be on together:
  // with only one on, the old mood board's Hybrid-only pop-up and the old
  // mood words are still reachable (1020g 二 (5)(b)).
  // 1020m 第五节: page 1 is on in production (the small-action row of
  // 1020m 第二节 has no switch of its own — it is part of page 1).
  ['app_config/feature_flags', 'homeLayoutV2Enabled', true,
    '第 3 批首页两页（#133），须和 moodRowV2Enabled 同开同关；1020m 小行动一行在里面'],
  ['app_config/feature_flags', 'moodRowV2Enabled', null,
    '第 3 批心情一行（#133），须和 homeLayoutV2Enabled 同开同关'],
  ['app_config/feature_flags', 'keyboardCompactHeaderEnabled', null,
    '1020c 键盘打开时顶栏变一行（#131），真机测过就开'],
  ['app_config/feature_flags', 'htmlReadersEnabled', null,
    '1020c 小讀本（#130），真机测不完就整项留到 Phase B 之后'],
  // 1020k (decisions-log 10/20 items 77–79): the lines before the reverse
  // items and the Weekly PR pages.  Expected value set by Junyu.
  ['app_config/feature_flags', 'scaleDirectionCuesEnabled', null,
    '1020k 反向题前的过渡句 + Weekly PR 反向三题固定第 3 页（两组相同），期望值待 Junyu 定'],
  // 1020l (1020j 一 (4)): research transcript of every chat turn.  Junyu
  // decides when (consent wording first); "—" until then.
  ['app_config/feature_flags', 'researchTranscriptEnabled', null,
    '1020l 对话原文存档（两组，老人看不到变化），期望值待 Junyu 定'],
  // 1020o 二 (4) / 四 (1): copy that can override the new FAQ answer 4 and
  // the reminiscence landing line.  Shown only; "—" = no expectation.
  ['app_config/usage_copy', 'faq_skip_checkin_answer_zh', null,
    '1020o 常見問題第 4 条；设了就盖住新答案'],
  ['app_config/usage_copy', 'reminiscence_landing_intro_zh', null,
    '1020o 人生點滴页顶一句；设了就盖住新文字'],
  ['app_config/feature_flags', 'sessionBriefPrV2Enabled', 'absent',
    '放错位置的键，应删掉（正确位置在 phase_b）'],
  ['app_config/phase_b', 'sessionBriefPrV2Enabled', true, 'T25 收尾按钮'],
  ['app_config/phase_b', 'weeklyScheduleV2Enabled', true, 'T24 每周问卷'],
  ['app_config/phase_b', 'socialContactProbeEnabled', true, '社会接触探针'],
  ['app_config/phase_b', 'weeklyPushHour', 10,
    '第 5 至 7 周 PGIC 推送 10:00（10/20 第 96 条）'],
  ['app_config/phase_a', 'sessionIdleTimeoutMin', 'absent',
    '测试残留，应删（正式 30 分钟来自 phase_b）'],
  ['app_config/phase_a', 'w2DayOffset', 'absent', '测试残留，应删'],
  ['app_config/phase_a', 'week1NudgeDays', 'absent', '测试残留，应删'],
  ['meta/memory_config', 'enabled', true, '记忆总开关'],
  ['meta/memory_config', 'phaseBArmA', true, 'Hybrid 组强制开记忆'],
  ['meta/memory_config', 'policy', 'C', '共享策略'],
  ['meta/memory_config', 'layersEnabled', true,
    '两层记忆（10/19 开，E1）'],
  ['meta/memory_config', 'extractionPrompt', 'absent',
    '不设 = v2（E2：维持 v2）'],
  ['meta/randomization_config', 'enabled', true, '登记 PB 靠它'],
  ['meta/randomization_config', 'sequenceUploadEnabled', false,
    '序列上传完要关（G1）'],
  ['meta/alert_config', 'enabled', true, 'T34 告警邮件'],
  ['meta/alert_config', 'primaryEmail', 'set', 'Junyu（只显示遮蔽后）'],
  ['meta/alert_config', 'backupEmail', 'absent', '决策 0041：不设备用'],
];

/** @param {*} v */
function show(key, v) {
  if (v === undefined) return '（没有）';
  if (/mail/i.test(key) && typeof v === 'string') {
    const [a, b] = v.split('@');
    return `${(a || '').slice(0, 2)}***@${b || '?'}`;
  }
  return JSON.stringify(v);
}

/** @return {string} ✓ / ✗ / — */
function verdict(expected, v) {
  if (expected === null) return '—';
  if (expected === 'absent') return v === undefined ? '✓' : '✗';
  // A switch that must be off: missing or literally false.
  if (expected === 'off') return v === undefined || v === false ? '✓' : '✗';
  if (expected === 'set') return (typeof v === 'string' && v) ? '✓' : '✗';
  return v === expected ? '✓' : '✗';
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const t = checkTarget(process.env, args);
  if (!t.ok) {
    console.error(t.reason);
    process.exit(2);
  }
  console.log(`目标：${t.reason}（只读）\n`);
  const admin = require('firebase-admin');
  admin.initializeApp({projectId: t.projectId});
  const db = admin.firestore();

  const docs = {};
  for (const path of [...new Set(CHECKS.map((c) => c[0]))]) {
    const snap = await db.doc(path).get();
    docs[path] = snap.exists ? (snap.data() || {}) : null;
  }
  let bad = 0;
  let lastDoc = '';
  for (const [doc, key, expected, note] of CHECKS) {
    if (doc !== lastDoc) {
      console.log(`\n${doc}${docs[doc] === null ? '  ← 文档不存在' : ''}`);
      lastDoc = doc;
    }
    const v = docs[doc] === null ? undefined : docs[doc][key];
    const ok = verdict(expected, v);
    if (ok === '✗') bad++;
    const exp = expected === null ? '' : `（期望 ${expected === 'absent' ?
      '没有' : expected === 'off' ? '没有或 false' : expected === 'set' ?
        '已填' : JSON.stringify(expected)}）`;
    console.log(`  ${ok} ${key} = ${show(key, v)} ${exp} ${note}`);
  }
  // Keys in these documents the checklist does not list (information).
  for (const [doc, data] of Object.entries(docs)) {
    if (!data) continue;
    const listed = new Set(CHECKS.filter((c) => c[0] === doc).map((c) => c[1]));
    const extra = Object.keys(data).filter((k) => !listed.has(k));
    if (extra.length) {
      console.log(`  ·  ${doc} 另有：` +
        extra.map((k) => `${k}=${show(k, data[k])}`).join('，'));
    }
  }

  // Allocation sequences (dev-tasks-1020 §C(4), 1020b §1(8)): per version
  // and stratum the stored length, the used positions and the sha256 —
  // read with a field mask, so the arms are never fetched.  v1 (PB-, the
  // run-in) is retired; v2 (RCT-) must be there before the first RCT-
  // registration (Qingyang uploads it 10/20 afternoon).
  console.log('\nrandomization_sequences（只看长度、已用、指纹）');
  for (const version of ['v1', 'v2']) {
    for (const s of ['low', 'high']) {
      const id = version === 'v1' ? s : `${version}_${s}`;
      const [snap] = await db.getAll(db.doc(`randomization_sequences/${id}`),
          {fieldMask: ['length', 'sha256']});
      if (!snap.exists) {
        const must = version === 'v2';
        console.log(`  ${must ? '✗' : '·'} ${version} ${s}：没有` +
          (must ? '（上传前没有是正常的）' : ''));
        if (must) bad++;
        continue;
      }
      const state = await db.doc(`randomization_state/${id}`).get();
      const next = state.exists ? Number(state.get('next')) || 0 : 0;
      const len = Number(snap.get('length')) || 0;
      const short = version === 'v2' && len < 80;
      if (short) bad++;
      console.log(`  ${short ? '✗' : '✓'} ${version} ${s}：${len} 个位置` +
        `${short ? '（少于 80）' : ''}，已用 ${next}，sha256 ` +
        `${snap.get('sha256') || '—'}`);
    }
  }
  for (const version of ['v1', 'v2']) {
    const v = await db.doc(`sequence_versions/${version}`).get();
    console.log(`  sequence_versions/${version}：` +
      (v.exists ? `${v.get('status')}` : '没有'));
  }

  // Tester accounts: count and masked ids only (G2).
  const testers = await db.collection('users').where('isTester', '==', true)
      .get();
  console.log(`\nisTester 帐号：${testers.size} 个` +
    (testers.size ? '（uid 前 6 位：' +
      testers.docs.map((d) => d.id.slice(0, 6)).join(', ') + '）' : ''));
  const enrolled = await db.collection('enrollments').get();
  console.log(`已登记（enrollments）：${enrolled.size} 人`);

  console.log(`\n${bad ? `${bad} 项和期望不同` : '全部符合期望'}`);
  process.exit(bad ? 1 : 0);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
