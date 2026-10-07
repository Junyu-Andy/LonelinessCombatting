/**
 * tool/firestore_target.js — shared "which Firestore am I about to touch?"
 * guard for the T19 scripts (same rule as tool/prelaunch_config.js).
 *
 * The emulator (FIRESTORE_EMULATOR_HOST set) is the default and the only
 * target that needs no extra flag.  A real project needs BOTH
 * --project=<id> and --production-confirm=<same id>.  The real project id
 * (loneliness-pilot-dev) is also the id the emulator tests use, so the id
 * alone proves nothing.
 */

'use strict';

function parseArgs(argv) {
  const out = {};
  for (const a of argv) {
    const m = a.match(/^--([^=]+)=(.*)$/);
    if (m) out[m[1]] = m[2];
    else if (a.startsWith('--')) out[a.slice(2)] = true;
  }
  return out;
}

/**
 * @return {{ok: boolean, reason: string, target?: string,
 *     projectId?: string}}
 */
function checkTarget(env, args) {
  if (env.FIRESTORE_EMULATOR_HOST) {
    if (args['production-confirm']) {
      return {ok: false, reason: '--production-confirm given but ' +
        'FIRESTORE_EMULATOR_HOST is set; refusing an ambiguous target'};
    }
    return {
      ok: true,
      reason: `emulator at ${env.FIRESTORE_EMULATOR_HOST}`,
      target: 'emulator',
      projectId: args.project || env.GCLOUD_PROJECT || 'demo-randomization',
    };
  }
  const project = typeof args.project === 'string' ? args.project : '';
  if (!project) {
    return {ok: false, reason: 'not on the emulator ' +
      '(FIRESTORE_EMULATOR_HOST unset) and no --project; refusing'};
  }
  if (project.startsWith('demo-')) {
    return {ok: false, reason: `${project} is a demo- project: it only ` +
      'exists in the emulator; set FIRESTORE_EMULATOR_HOST'};
  }
  if (args['production-confirm'] !== project) {
    return {ok: false, reason: `refusing to touch real project ${project}. ` +
      `Add --production-confirm=${project} (see ` +
      'docs/release/prelaunch-checklist.md)'};
  }
  return {ok: true, reason: `REAL PROJECT ${project}`, target: 'production',
    projectId: project};
}

module.exports = {parseArgs, checkTarget};
