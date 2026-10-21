/**
 * tool/dashboard/public/auth.js — Junyu's App login in the browser, and
 * the two existing server entry points the dashboard may call (decision
 * 0061; 1020i 第二版 §2.5).
 *
 *   - Sign-in: Firebase Auth REST (email + password, as in the App).  The
 *     password goes straight to Google; the tokens live in this page's
 *     memory only (no storage), so closing the page signs out.
 *   - Calls: only acknowledgeAlert and markSafetyFalseAlarm, over the
 *     callable protocol (POST {data}, Bearer ID token) — the same entry
 *     points, role check (`unblinded`) and alert_audit_log as the App's
 *     researcher page.  Any other name is refused here.
 *
 * Works in the browser (window.DashboardAuth) and in Node (tests).
 */
(function(root, factory) {
  if (typeof module === 'object' && module.exports) module.exports = factory();
  else root.DashboardAuth = factory();
})(typeof self !== 'undefined' ? self : this, function() {
  'use strict';

  const CALLABLES = ['acknowledgeAlert', 'markSafetyFalseAlarm'];
  /** Refresh the ID token when it has less than this left. */
  const REFRESH_MARGIN_MS = 5 * 60 * 1000;

  const MESSAGES = {
    INVALID_LOGIN_CREDENTIALS: '电邮或密码不对。',
    EMAIL_NOT_FOUND: '电邮或密码不对。',
    INVALID_PASSWORD: '电邮或密码不对。',
    INVALID_EMAIL: '电邮格式不对。',
    USER_DISABLED: '这个账号已停用。',
    TOO_MANY_ATTEMPTS_TRY_LATER: '试太多次了，请过几分钟再试。',
    UNAUTHENTICATED: '登录已过期，请重新登录。',
    PERMISSION_DENIED: '这个账号没有权限（要 unblinded 角色）。',
    FAILED_PRECONDITION: '服务器开关没开（标记误触要 safetyFalseAlarmMarkEnabled）。',
    NOT_FOUND: '找不到这条告警（可能已删除）。',
    INVALID_ARGUMENT: '请求不完整。',
  };

  function errorText(code, fallback) {
    const key = String(code || '').split(' ')[0].split(':')[0];
    return MESSAGES[key] || fallback || `出错了（${code || '未知'}）。`;
  }

  function fail(code, message) {
    const e = new Error(errorText(code, message));
    e.code = code;
    return e;
  }

  /**
   * @param {{apiKey: string, projectId: string, region: string,
   *     authEmulator: ?string, functionsEmulator: ?string}} cfg
   * @param {function} fetchFn
   * @param {function(): number=} clock
   */
  function createAuth(cfg, fetchFn, clock) {
    const now = clock || (() => Date.now());
    let session = null;

    const authRoot = cfg.authEmulator ? `http://${cfg.authEmulator}/` :
      'https://';
    const signInUrl = `${authRoot}identitytoolkit.googleapis.com/v1/` +
      `accounts:signInWithPassword?key=${encodeURIComponent(cfg.apiKey)}`;
    const refreshUrl = `${authRoot}securetoken.googleapis.com/v1/token?key=` +
      encodeURIComponent(cfg.apiKey);

    function functionUrl(name) {
      if (cfg.functionsEmulator) {
        return `http://${cfg.functionsEmulator}/${cfg.projectId}/` +
          `${cfg.region}/${name}`;
      }
      return `https://${cfg.region}-${cfg.projectId}.cloudfunctions.net/${name}`;
    }

    async function readJson(res) {
      try {
        return await res.json();
      } catch (_) {
        return {};
      }
    }

    function remember(email, idToken, refreshToken, expiresIn) {
      session = {
        email,
        idToken,
        refreshToken,
        expiresAt: now() + Number(expiresIn || 3600) * 1000,
      };
    }

    async function signIn(email, password) {
      const res = await fetchFn(signInUrl, {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({email, password, returnSecureToken: true}),
      });
      const body = await readJson(res);
      if (!res.ok) {
        throw fail(body.error && body.error.message, '登录失败。');
      }
      remember(body.email || email, body.idToken, body.refreshToken,
          body.expiresIn);
      return {email: session.email};
    }

    async function idToken() {
      if (!session) throw fail('UNAUTHENTICATED');
      if (session.expiresAt - now() > REFRESH_MARGIN_MS) return session.idToken;
      const res = await fetchFn(refreshUrl, {
        method: 'POST',
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: `grant_type=refresh_token&refresh_token=${
          encodeURIComponent(session.refreshToken)}`,
      });
      const body = await readJson(res);
      if (!res.ok) {
        session = null;
        throw fail('UNAUTHENTICATED');
      }
      remember(session.email, body.id_token, body.refresh_token,
          body.expires_in);
      return session.idToken;
    }

    /** One of CALLABLES; returns the callable's `result`. */
    async function call(name, data) {
      if (CALLABLES.indexOf(name) < 0) throw new Error(`not allowed: ${name}`);
      const token = await idToken();
      const res = await fetchFn(functionUrl(name), {
        method: 'POST',
        headers: {'Content-Type': 'application/json',
          'Authorization': `Bearer ${token}`},
        body: JSON.stringify({data}),
      });
      const body = await readJson(res);
      if (!res.ok || body.error) {
        const err = body.error || {};
        if (res.status === 401) session = null;
        throw fail(err.status || (res.status === 401 ? 'UNAUTHENTICATED' : ''),
            err.message);
      }
      return body.result;
    }

    return {
      signIn,
      call,
      functionUrl,
      signOut() {
        session = null;
      },
      current() {
        return session ? {email: session.email} : null;
      },
    };
  }

  return {CALLABLES, MESSAGES, errorText, createAuth};
});
