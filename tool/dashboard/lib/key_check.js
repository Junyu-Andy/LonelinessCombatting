/**
 * tool/dashboard/lib/key_check.js — before the dashboard reads anything
 * from the real project, ask Google which Firestore permissions the
 * service-account key has (Resource Manager testIamPermissions: reads and
 * writes no data, needs no permission of its own).  Decision 0061 /
 * 10/20 第 65 条 (6): a key that can write is refused — the dashboard
 * must run on its own viewer-only account, not the admin key.
 */
'use strict';

const WRITE_PERMISSIONS = ['datastore.entities.create',
  'datastore.entities.update', 'datastore.entities.delete'];
const READ_PERMISSIONS = ['datastore.entities.get', 'datastore.entities.list'];

/**
 * Pure: the verdict from the granted list.
 * @param {Array<string>} granted
 * @return {{ok: boolean, reason: string}}
 */
function verdict(granted) {
  const g = granted || [];
  const writes = WRITE_PERMISSIONS.filter((p) => g.indexOf(p) >= 0);
  if (writes.length) {
    return {ok: false, reason: `这把钥匙能写 Firestore（${writes.join('、')}）。` +
      '看板只能用只读服务账号（roles/datastore.viewer），见说明第一节。'};
  }
  const reads = READ_PERMISSIONS.filter((p) => g.indexOf(p) >= 0);
  if (reads.length < READ_PERMISSIONS.length) {
    return {ok: false, reason: '这把钥匙不能读 Firestore。请给服务账号加上' +
      ' roles/datastore.viewer 角色。'};
  }
  return {ok: true, reason: '只读钥匙'};
}

/**
 * @param {{projectId: string, getAccessToken: function(): Promise<string>,
 *     fetch: function}} deps
 * @return {Promise<{ok: boolean, reason: string}>}
 */
async function checkKey(deps) {
  let token;
  try {
    token = await deps.getAccessToken();
  } catch (err) {
    return {ok: false, reason: `读不了钥匙：${err && err.message}`};
  }
  const url = 'https://cloudresourcemanager.googleapis.com/v1/projects/' +
    `${deps.projectId}:testIamPermissions`;
  let res;
  try {
    res = await deps.fetch(url, {
      method: 'POST',
      headers: {'Authorization': `Bearer ${token}`,
        'Content-Type': 'application/json'},
      body: JSON.stringify({
        permissions: WRITE_PERMISSIONS.concat(READ_PERMISSIONS),
      }),
    });
  } catch (err) {
    return {ok: false, reason: `连不上 Google 检查钥匙权限：${err && err.message}`};
  }
  if (!res.ok) {
    let msg = '';
    try {
      msg = (await res.json()).error.message;
    } catch (_) {
      msg = `HTTP ${res.status}`;
    }
    return {ok: false, reason: `检查钥匙权限失败：${msg}。` +
      '如果提示 Cloud Resource Manager API 没开，在 Google Cloud 控制台打开它' +
      '（只要开一次）。'};
  }
  const body = await res.json();
  return verdict(body.permissions || []);
}

module.exports = {WRITE_PERMISSIONS, READ_PERMISSIONS, verdict, checkKey};
