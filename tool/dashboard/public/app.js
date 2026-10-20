/**
 * tool/dashboard/public/app.js — the dashboard pages (1020i 第二版 §2.2).
 * Plain DOM, no libraries; data from the local server's /api/*.  Every
 * value is set as text (never as HTML).
 */
(function() {
  'use strict';

  const ARM = {A: 'A（Hybrid）', B: 'B（规则）'};
  const COMPANION = {siu_yan: '小欣', ah_jan_ah_bak: '阿珍阿伯',
    tung_tung: '通通'};
  const COMPANIONS = ['siu_yan', 'ah_jan_ah_bak', 'tung_tung'];
  const STAGE = {whatsapp: '发 WhatsApp', phone: '打电话',
    follow_up_period: '随访期', none: '—'};
  const CELL = {not_yet: '未开始', open: '未做完', missed: '已过时间',
    done: '已完成', skipped: '已完成（跳过）', not_built: '未做'};
  const LEVEL = {acute: '急性', moderate: '中度', low: '轻度'};
  const SOURCE_GROUP = {participant_input: '老人输入',
    ai_reply_scan: '夥伴回复扫描', questionnaire: '问卷',
    assessor_entry: '评估员录入'};
  const SESSION_TYPE = {free_chat: '傾偈', check_in: 'check-in',
    reminiscence: '回忆'};
  const BRIEF_STATUS = {completed: '完成', partially_completed: '部分完成',
    skipped: '跳过', expired: '过期', due_not_invited: '该邀未邀'};
  const ACK_HINT = '标误触不等于确认：标了误触，告警还算「未确认」，' +
    '12 小时后照样发升级邮件。两件事要分开按。';

  let config = null;
  let auth = null;
  let showTesters = false;
  const view = document.getElementById('view');

  // ---------------------------------------------------------------- DOM

  function h(tag, attrs, ...children) {
    const el = document.createElement(tag);
    for (const [k, v] of Object.entries(attrs || {})) {
      if (v === null || v === undefined || v === false) continue;
      if (k === 'class') el.className = v;
      else if (k.startsWith('on')) el.addEventListener(k.slice(2), v);
      else el.setAttribute(k, v === true ? '' : v);
    }
    for (const c of children.flat()) {
      if (c === null || c === undefined || c === false) continue;
      el.append(c instanceof Node ? c : document.createTextNode(String(c)));
    }
    return el;
  }

  function pill(kind, label) {
    return h('span', {class: `pill ${kind}`}, label);
  }

  /** "MM-DD HH:mm" in Hong Kong. */
  function hk(isoString) {
    if (!isoString) return '—';
    const d = new Date(new Date(isoString).getTime() + 8 * 3600 * 1000);
    return d.toISOString().slice(5, 16).replace('T', ' ');
  }

  function dash(v) {
    return v === null || v === undefined || v === '' ? '—' : v;
  }

  /**
   * A sortable table.  columns: [{label, get(row) → sortable value,
   * cell(row) → node/text (default get), num, nosort}].
   */
  function table(columns, rows, opts) {
    const o = opts || {};
    let sortIdx = o.sortIdx === undefined ? -1 : o.sortIdx;
    let asc = true;
    const tbody = h('tbody');
    function render() {
      const sorted = rows.slice();
      if (sortIdx >= 0) {
        const get = columns[sortIdx].get;
        sorted.sort((a, b) => {
          const x = get(a);
          const y = get(b);
          if (x === y) return 0;
          if (x === null || x === undefined) return 1;
          if (y === null || y === undefined) return -1;
          return (x < y ? -1 : 1) * (asc ? 1 : -1);
        });
      }
      tbody.replaceChildren(...sorted.map((r) => h('tr', null,
          columns.map((c) => h('td', {class: c.num ? 'num' : null},
              c.cell ? c.cell(r) : dash(c.get(r)))))));
    }
    const head = h('tr', null, columns.map((c, i) => h('th', {
      class: c.nosort ? 'nosort' : null,
      onclick: c.nosort ? null : () => {
        if (sortIdx === i) asc = !asc;
        else {
          sortIdx = i;
          asc = true;
        }
        render();
      },
    }, c.label)));
    render();
    if (!rows.length) {
      return h('div', {class: 'empty'}, o.empty || '没有。');
    }
    return h('div', {class: 'table-wrap'}, h('table', null, h('thead', null,
        head), tbody));
  }

  // ---------------------------------------------------------------- data

  async function api(path, method) {
    const res = await fetch(path, {method: method || 'GET',
      headers: method === 'POST' ? {'Content-Type': 'application/json'} : {}});
    let body = {};
    try {
      body = await res.json();
    } catch (_) {
      body = {};
    }
    if (!res.ok) throw new Error(body.error || `HTTP ${res.status}`);
    return body;
  }

  function setDataTime(generatedAt) {
    document.getElementById('data-time').textContent = generatedAt ?
      `数据时间 ${hk(generatedAt)}（${config.cacheMinutes} 分钟内不重读）` : '';
  }

  // ---------------------------------------------------------------- login

  function updateLoginState() {
    const cur = auth && auth.current();
    document.getElementById('login-state').textContent = cur ?
      `已登录：${cur.email}` : '';
    document.getElementById('logout').classList.toggle('hidden', !cur);
  }

  function askLogin() {
    return new Promise((resolve) => {
      const panel = document.getElementById('login-panel');
      const form = document.getElementById('login-form');
      const err = document.getElementById('login-error');
      err.textContent = '';
      panel.classList.remove('hidden');
      document.getElementById('login-email').focus();
      const done = (ok) => {
        form.onsubmit = null;
        document.getElementById('login-cancel').onclick = null;
        panel.classList.add('hidden');
        document.getElementById('login-password').value = '';
        resolve(ok);
      };
      form.onsubmit = async (ev) => {
        ev.preventDefault();
        err.textContent = '';
        try {
          await auth.signIn(document.getElementById('login-email').value.trim(),
              document.getElementById('login-password').value);
          updateLoginState();
          done(true);
        } catch (e) {
          err.textContent = e.message;
        }
      };
      document.getElementById('login-cancel').onclick = () => done(false);
    });
  }

  /** 確認處理 / 標記誤觸 through the existing callables. */
  async function alertAction(kind, alert, button) {
    const name = kind === 'ack' ? 'acknowledgeAlert' : 'markSafetyFalseAlarm';
    const what = kind === 'ack' ? '確認處理' : '標記誤觸';
    const who = alert.researchId || '（无研究编号）';
    if (!window.confirm(`${what}：${who}，${LEVEL[alert.level] || alert.level}，` +
      `${hk(alert.createdAt)}？\n\n${ACK_HINT}`)) return;
    if (!auth.current() && !(await askLogin())) return;
    button.disabled = true;
    try {
      const result = await auth.call(name, {alertId: alert.alertId});
      const again = result && (result.alreadyAcknowledged || result.alreadyMarked);
      window.alert(again ? `这条之前已经${what}过。` : `${what}完成。`);
      await api('/api/refresh', 'POST');
      route();
    } catch (e) {
      updateLoginState();
      window.alert(`${what}没有成功：${e.message}`);
      button.disabled = false;
    }
  }

  function alertButtons(a) {
    if (config.emulator && !config.functionsEmulator) {
      return h('span', {class: 'muted'}, '演示模式：不能按');
    }
    const ack = a.acknowledgedAt ? null : h('button', {class: 'primary',
      type: 'button'}, '確認處理');
    const mark = a.falseAlarm ? pill('none', '已标误触') :
      h('button', {class: 'danger', type: 'button'}, '標記誤觸');
    if (ack) ack.addEventListener('click', () => alertAction('ack', a, ack));
    if (mark.tagName === 'BUTTON') {
      mark.addEventListener('click', () => alertAction('mark', a, mark));
    }
    return h('div', {class: 'actions'}, ack || pill('done', `已确认 ${hk(a.acknowledgedAt)}`),
        mark);
  }

  function alertTable(alerts, withId) {
    const cols = [];
    if (withId) {
      cols.push({label: '研究编号', get: (a) => a.researchId,
        cell: (a) => a.researchId ? personLink(a.researchId) : '（无编号）'});
    }
    cols.push(
        {label: '时间', get: (a) => a.createdAt, cell: (a) => hk(a.createdAt)},
        {label: '研究日', get: (a) => a.studyDay, num: true},
        {label: '级别', get: (a) => a.level,
          cell: (a) => pill(a.level === 'acute' ? 'bad' : 'open',
              LEVEL[a.level] || dash(a.level))},
        {label: '类别', get: (a) => a.category},
        {label: '来源', get: (a) => SOURCE_GROUP[a.sourceGroup] || a.source},
        {label: '升级邮件', get: (a) => a.escalatedAt,
          cell: (a) => a.escalatedAt ? hk(a.escalatedAt) : '—'},
        {label: '操作', get: () => 0, nosort: true, cell: alertButtons});
    return h('div', null, h('p', {class: 'note'}, ACK_HINT),
        table(cols, alerts, {empty: '没有未确认的告警。'}));
  }

  function personLink(rid) {
    return h('a', {href: `#/person/${encodeURIComponent(rid)}`}, rid);
  }

  // ---------------------------------------------------------------- pages

  async function renderOverview() {
    const data = await api(`/api/overview${showTesters ? '?testers=1' : ''}`);
    setDataTime(data.generatedAt);
    // One cell per period: the total, then 小欣 / 阿珍阿伯 / 通通.
    const sessionsCol = (key, label) => ({
      label: `${label}有效会话`, num: true,
      get: (r) => r.validSessions[key].total,
      cell: (r) => `${r.validSessions[key].total}（` +
        COMPANIONS.map((c) => r.validSessions[key][c]).join('/') + '）',
    });
    const cols = [
      {label: '研究编号', get: (r) => r.researchId,
        cell: (r) => personLink(r.researchId)},
      {label: 'cohort', get: (r) => r.cohort},
      {label: '组别', get: (r) => r.arm, cell: (r) => ARM[r.arm] || dash(r.arm)},
      {label: '登记日', get: (r) => r.enrolledDate},
      {label: '研究日', get: (r) => r.studyDay, num: true,
        cell: (r) => r.studyDay < 1 ? '未开始' : `第 ${r.studyDay} 天`},
      {label: '最后打开', get: (r) => r.lastOpenAt,
        cell: (r) => hk(r.lastOpenAt) + (r.legacyBasis ? '（旧构建口径）' : '')},
      {label: '跟进', get: (r) => r.stage,
        cell: (r) => r.stage === 'none' ? '—' :
          pill(r.stage, `${STAGE[r.stage]}（${r.consecutiveUnopenedDays} 天）`)},
    ].concat([sessionsCol('thisWeek', '本周'), sessionsCol('all', '累计')])
        .concat([
          {label: 'Brief PR 邀请/完成', get: (r) => r.briefPr.invited,
            cell: (r) => `${r.briefPr.invited} / ${r.briefPr.completed}`},
          {label: '本周 check-in', get: (r) => r.checkIn.daysThisWeek,
            cell: (r) => `${r.checkIn.daysThisWeek} / ${r.checkIn.daysSoFar} 天`},
        ])
        .concat(['W1', 'W2', 'W3', 'W4'].map((w) => ({
          label: `Weekly PR ${w}`, get: (r) => r.weeklyPr[w],
          cell: (r) => pill(r.weeklyPr[w], CELL[r.weeklyPr[w]] || r.weeklyPr[w]),
        })))
        .concat([
          {label: 'W8', get: (r) => r.w8, cell: (r) => pill(r.w8, CELL[r.w8])},
          {label: '未确认告警', num: true, get: (r) => r.pendingAlerts,
            cell: (r) => r.pendingAlerts ? pill('bad', String(r.pendingAlerts)) :
              '0'},
        ]);
    const testerBox = h('input', {type: 'checkbox', id: 'show-testers',
      checked: showTesters || null});
    testerBox.addEventListener('change', () => {
      showTesters = testerBox.checked;
      route();
    });
    const out = [
      h('h2', null, `总览（${data.people.length} 人，今天 ${data.today}）`),
      h('div', {class: 'controls'},
          h('label', null, testerBox, ' 显示测试账号'),
          h('span', {class: 'muted'},
              '有效会话从研究第 1 天算起，括号里是小欣 / 阿珍阿伯 / 通通；' +
              '「每周问卷」一格只看 Weekly PR（过程数据）。' +
              '结局问卷的完成情况见「今天要做」和「结局完成率」，不和组别放在一起。')),
      table(cols, data.people, {sortIdx: 0, empty: '还没有登记的参与者。'}),
    ];
    if (data.testers) {
      out.push(h('h3', null, `测试账号（${data.testers.length}）`),
          table([
            {label: '账号（前 6 位）', get: (r) => r.testerId},
            {label: '组别（测试员自选）', get: (r) => r.arm,
              cell: (r) => ARM[r.arm] || dash(r.arm)},
            {label: '最后打开', get: (r) => r.lastOpenAt,
              cell: (r) => hk(r.lastOpenAt)},
            {label: '累计有效会话', num: true,
              get: (r) => r.validSessions.all.total},
            {label: '未确认告警', num: true, get: (r) => r.pendingAlerts},
          ], data.testers, {empty: '没有测试账号。'}));
    }
    return out;
  }

  async function renderToday() {
    const data = await api('/api/today');
    setDataTime(data.generatedAt);
    const unopened = (rows, empty) => table([
      {label: '研究编号', get: (r) => r.researchId,
        cell: (r) => personLink(r.researchId)},
      {label: '连续没打开', num: true, get: (r) => r.consecutiveUnopenedDays,
        cell: (r) => `${r.consecutiveUnopenedDays} 天`},
    ], rows, {empty});
    return [
      h('h2', null, `今天要做（${data.today}）`),
      h('p', {class: 'muted'}, '跟进只算研究第 1 至 28 天（和 App 运营看板相同）。名单里不显示组别。'),
      h('h3', null, `(a) 发 WhatsApp：连续 3 至 5 天没打开（${data.whatsapp.length}）`),
      unopened(data.whatsapp, '今天没有。'),
      h('h3', null, `(b) 打电话：连续 6 天及以上没打开（${data.phone.length}）`),
      unopened(data.phone, '今天没有。'),
      h('h3', null, `(c) 每周问卷今天是最后一天，还没做完（${data.weeklyDue.length}）`),
      h('p', {class: 'muted'}, '和每天 10:00 的提醒邮件同一个规则：W1 至 W3 的第 9、16、23 天，W4 的第 28 天。'),
      table([
        {label: '研究编号', get: (r) => r.researchId,
          cell: (r) => personLink(r.researchId)},
        {label: '研究日', num: true, get: (r) => r.studyDay},
        {label: '问卷', get: (r) => r.bundle,
          cell: (r) => `第 ${r.questionnaireWeek} 周（${r.bundle}）`},
      ], data.weeklyDue, {empty: '今天没有。'}),
      h('h3', null, `(d) 未确认的安全告警（${data.alerts.length}）`),
      alertTable(data.alerts, true),
    ];
  }

  async function renderPerson(rid) {
    const data = await api(`/api/person?id=${encodeURIComponent(rid)}`);
    setDataTime(data.generatedAt);
    const p = data.person;
    const facts = h('div', {class: 'facts'},
        h('span', null, '组别 ', h('b', null, ARM[p.arm] || dash(p.arm))),
        h('span', null, 'cohort ', h('b', null, dash(p.cohort))),
        h('span', null, '登记日 ', h('b', null, dash(p.enrolledDate))),
        h('span', null, 'W0 ', h('b', null, p.w0Date)),
        h('span', null, '研究日 ', h('b', null,
            p.studyDay < 1 ? '未开始' : `第 ${p.studyDay} 天（第 ${p.studyWeek} 周）`)),
        h('span', null, '最后打开 ', h('b', null, hk(p.lastOpenAt))),
        h('span', null, '跟进 ', h('b', null, p.stage === 'none' ? '—' :
          `${STAGE[p.stage]}（${p.consecutiveUnopenedDays} 天没打开）`)),
        h('span', null, 'Weekly PR ', h('b', null, ['W1', 'W2', 'W3', 'W4']
            .map((w) => `${w} ${CELL[p.weeklyPr[w]]}`).join('，'))));
    const pendingSafety = data.safety.filter((s) => s.alert &&
      !s.alert.acknowledgedAt);
    return [
      h('p', null, h('a', {href: '#/overview'}, '← 回总览')),
      h('h2', null, p.researchId),
      h('div', {class: 'panel'}, facts),
      h('h3', null, `安全事件（${data.safety.length}，未确认 ${pendingSafety.length}）`),
      h('p', {class: 'note'}, ACK_HINT),
      table([
        {label: '时间', get: (s) => s.createdAt, cell: (s) => hk(s.createdAt)},
        {label: '级别', get: (s) => s.level, cell: (s) => LEVEL[s.level] || dash(s.level)},
        {label: '类别', get: (s) => s.category},
        {label: '来源', get: (s) => s.sourceGroup,
          cell: (s) => SOURCE_GROUP[s.sourceGroup] || dash(s.source)},
        {label: '误触', get: (s) => s.falseAlarm, cell: (s) => s.falseAlarm ? '已标' : '—'},
        {label: '告警', get: (s) => s.alert ? (s.alert.acknowledgedAt || '0') : null,
          nosort: true,
          cell: (s) => s.alert ? alertButtons(s.alert) : '（没有告警）'},
      ], data.safety, {empty: '没有安全事件。'}),
      h('h3', null, '每日'),
      table([
        {label: '日期', get: (d) => d.dayKey},
        {label: '研究日', num: true, get: (d) => d.studyDay},
        {label: '打开', get: (d) => d.opened, cell: (d) => d.opened ? '✓' : '—'},
        {label: '第一次打开', get: (d) => d.firstOpenAt},
        {label: '前台分钟', num: true, get: (d) => d.foregroundMinutes},
      ].concat(COMPANIONS.map((c) => ({label: `有效会话 ${COMPANION[c]}`, num: true,
        get: (d) => d.validSessions[c]}))).concat([
        {label: 'Brief PR 邀请/完成', get: (d) => d.briefPrInvited,
          cell: (d) => `${d.briefPrInvited} / ${d.briefPrCompleted}`},
        {label: 'check-in', get: (d) => d.checkInDone,
          cell: (d) => d.checkInDone ? '✓' : '—'},
        {label: '心情（只看有没有记）', get: (d) => d.moodRecorded,
          cell: (d) => d.moodRecorded ? '有记' : '—'},
      ]), data.days, {empty: '还没到研究第 1 天。'}),
      h('h3', null, `会话（${data.sessions.length}）`),
      table([
        {label: '开始', get: (s) => s.startedAt, cell: (s) => hk(s.startedAt)},
        {label: '研究日', num: true, get: (s) => s.studyDay},
        {label: '陪伴者', get: (s) => COMPANION[s.agentId] || s.agentId},
        {label: '类型', get: (s) => SESSION_TYPE[s.sessionType] || s.sessionType},
        {label: '分钟', num: true, get: (s) => s.durationMinutes},
        {label: '老人发言', num: true, get: (s) => s.userMessageCount},
        {label: '有效', get: (s) => s.isValid, cell: (s) => s.isValid ? '✓' : '—'},
        {label: '结束原因', get: (s) => s.endReason},
        {label: 'Brief PR', get: (s) => s.briefPrStatus,
          cell: (s) => BRIEF_STATUS[s.briefPrStatus] || dash(s.briefPrStatus)},
      ], data.sessions, {empty: '还没有会话。'}),
      h('h3', null, `Brief PR（${data.briefPr.length}）`),
      table([
        {label: '邀请', get: (b) => b.invitedAt, cell: (b) => hk(b.invitedAt)},
        {label: '研究日', num: true, get: (b) => b.studyDay},
        {label: '陪伴者', get: (b) => COMPANION[b.agentId] || b.agentId},
        {label: '状态', get: (b) => b.finalStatus,
          cell: (b) => BRIEF_STATUS[b.finalStatus] || dash(b.finalStatus)},
        {label: '理解', num: true, get: (b) => b.understanding},
        {label: '认可', num: true, get: (b) => b.validation},
        {label: '关心', num: true, get: (b) => b.caring},
        {label: '不体贴', num: true, get: (b) => b.insensitivity},
      ], data.briefPr, {empty: '还没有 Brief PR。'}),
    ];
  }

  async function renderCompletion() {
    const data = await api('/api/completion');
    setDataTime(data.generatedAt);
    const rate = (r) => {
      if (r.notBuilt) return 'App 里还没有 W8';
      if (r.notScheduled) return '没有排这一项';
      if (r.suppressed) return `少于 ${data.minN} 人，不显示`;
      return `${Math.round(r.rate * 100)}%（${r.completed} / ${r.n}）`;
    };
    return [
      h('h2', null, '结局完成率（全体合并，不分组）'),
      h('p', {class: 'muted'},
          `只算 Phase B（RCT- 和 PB-，不含 PILOT）。App 内问卷算窗口已经结束的人；` +
          `W4 纸本算研究第 ${data.w4DueFromDay} 天及以后的人。少于 ${data.minN} 人不显示。只数完成与否，不读答案。`),
      table([
        {label: '问卷', get: (r) => r.instrument},
        {label: '时间点', get: (r) => r.timepoint,
          cell: (r) => r.paper ? `${r.timepoint}（纸本）` : r.timepoint},
        {label: '完成率', get: (r) => (r.rate === undefined ? null : r.rate),
          cell: rate},
      ], data.rows),
    ];
  }

  function renderExport() {
    const status = h('div', {class: 'panel'}, '按下面的按钮导出。');
    const button = h('button', {class: 'primary', type: 'button'}, '导出 CSV');
    button.addEventListener('click', async () => {
      button.disabled = true;
      status.textContent = '正在导出……人多时要一两分钟。';
      try {
        const r = await api('/api/export', 'POST');
        status.replaceChildren(h('p', null, `已导出 ${r.people} 人：`),
            h('ul', null, r.files.map((f) => h('li', null, f))));
      } catch (e) {
        status.textContent = `导出失败：${e.message}`;
      }
      button.disabled = false;
    });
    return [
      h('h2', null, '导出过程数据（CSV）'),
      h('p', null, '两份文件，存到仓库以外的固定文件夹：'),
      h('ul', null,
          h('li', null, 'process_weekly：每人每个研究周一行（打开天数、前台分钟、有效会话、Brief PR、check-in 天数、记了心情的天数）；'),
          h('li', null, 'process_daily：每人每天一行，和 App 运营看板导出的列相同。')),
      h('p', {class: 'muted'}, '只有过程数据和组别；没有结局答案、心情值、对话。'),
      button, status,
    ];
  }

  // ---------------------------------------------------------------- router

  async function route() {
    const hash = location.hash || '#/overview';
    const parts = hash.slice(2).split('/');
    const name = parts[0] || 'overview';
    for (const a of document.querySelectorAll('#nav a')) {
      a.classList.toggle('active', a.dataset.view === name);
    }
    view.replaceChildren(h('p', {class: 'muted'}, '读取中……'));
    try {
      let nodes;
      if (name === 'today') nodes = await renderToday();
      else if (name === 'person') nodes = await renderPerson(decodeURIComponent(parts[1] || ''));
      else if (name === 'completion') nodes = await renderCompletion();
      else if (name === 'export') nodes = renderExport();
      else nodes = await renderOverview();
      view.replaceChildren(...nodes);
    } catch (e) {
      view.replaceChildren(h('p', {class: 'error'}, `读取失败：${e.message}`));
    }
  }

  async function start() {
    config = await api('/api/config');
    auth = window.DashboardAuth.createAuth(config, (u, o) => fetch(u, o));
    if (config.emulator) {
      const badge = document.getElementById('mode-badge');
      badge.textContent = '演示：模拟器 + 合成数据';
      badge.classList.add('demo');
    }
    document.getElementById('refresh').addEventListener('click', async () => {
      await api('/api/refresh', 'POST');
      route();
    });
    document.getElementById('logout').addEventListener('click', () => {
      auth.signOut();
      updateLoginState();
    });
    window.addEventListener('hashchange', route);
    updateLoginState();
    route();
  }

  start().catch((e) => {
    view.replaceChildren(h('p', {class: 'error'}, `打不开看板：${e.message}`));
  });
})();
