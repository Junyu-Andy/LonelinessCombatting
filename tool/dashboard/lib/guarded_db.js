/**
 * tool/dashboard/lib/guarded_db.js — the only way the dashboard touches
 * Firestore (decisions 0061, 0072).  Read only:
 *
 *   - a query names a path template from fields.READ_ALLOW; anything else
 *     (and anything in DENIED_COLLECTIONS) throws before Firestore is
 *     called;
 *   - every query gets that template's field mask (`select`), so fields
 *     not listed — answers, scores, conversation — never leave
 *     Firestore;
 *   - `where` / `orderBy` only on listed fields (or the document id);
 *     `users/{uid}/events` only by name, from EVENT_NAMES;
 *   - there is no set / update / add / delete / batch / transaction.
 *
 * Results are plain {id, data} objects.  `onRead(template, rows)` (tests)
 * sees every row that came back.
 */
'use strict';

const fields = require('./fields');

const ID = /^[A-Za-z0-9_-]{1,128}$/;
const OPS = ['==', '>=', '>', '<=', '<', 'in'];

function guardError(msg) {
  const e = new Error(`dashboard read refused: ${msg}`);
  e.guard = true;
  return e;
}

/** Throws when any segment of a path names a denied collection. */
function assertNotDenied(path) {
  for (const seg of path.split('/')) {
    if (fields.DENIED_COLLECTIONS.indexOf(seg) >= 0) {
      throw guardError(`denied collection ${seg}`);
    }
  }
}

/**
 * @param {object} db admin.firestore()
 * @param {{onRead: (function(string, Array<object>)|undefined),
 *     FieldPath: object}} opts
 * @return {{query: function(string, object=): Query,
 *     config: function(string): Promise<object>}}
 */
function guardedDb(db, opts) {
  const o = opts || {};
  const FieldPath = o.FieldPath;

  function resolve(template, params) {
    assertNotDenied(template);
    const allowed = fields.READ_ALLOW[template];
    if (!allowed) throw guardError(`not on the allowlist: ${template}`);
    const path = template.replace(/\{(\w+)\}/g, (m, k) => {
      const v = params && params[k];
      if (typeof v !== 'string' || !ID.test(v)) {
        throw guardError(`bad path parameter ${k}`);
      }
      return v;
    });
    assertNotDenied(path);
    return {path, allowed};
  }

  /** A query on one allowlisted collection; immutable, chainable. */
  class Query {
    constructor(template, path, allowed, steps) {
      this._template = template;
      this._path = path;
      this._allowed = allowed;
      this._steps = steps;
    }

    _with(step) {
      return new Query(this._template, this._path, this._allowed,
          this._steps.concat([step]));
    }

    _field(f) {
      if (f === '__id__') return FieldPath.documentId();
      if (this._allowed.indexOf(f) < 0) {
        throw guardError(`field ${f} not readable on ${this._template}`);
      }
      return f;
    }

    where(f, op, v) {
      if (OPS.indexOf(op) < 0) throw guardError(`operator ${op}`);
      if (this._template === 'users/{uid}/events') {
        const names = op === 'in' ? v : [v];
        if (f !== 'name' || !Array.isArray(names) || !names.every((n) =>
          fields.EVENT_NAMES.indexOf(n) >= 0)) {
          throw guardError('events may only be read by name');
        }
      }
      return this._with(['where', this._field(f), op, v]);
    }

    orderBy(f, dir) {
      return this._with(['orderBy', this._field(f), dir || 'asc']);
    }

    limit(n) {
      if (!Number.isInteger(n) || n < 1) throw guardError('limit');
      return this._with(['limit', n]);
    }

    _build() {
      if (this._template === 'users/{uid}/events' &&
        !this._steps.some((s) => s[0] === 'where' && s[1] === 'name')) {
        throw guardError('events may only be read by name');
      }
      let q = db.collection(this._path);
      for (const s of this._steps) {
        if (s[0] === 'where') q = q.where(s[1], s[2], s[3]);
        else if (s[0] === 'orderBy') q = q.orderBy(s[1], s[2]);
        else if (s[0] === 'limit') q = q.limit(s[1]);
      }
      return q.select(...this._allowed);
    }

    /** @return {Promise<Array<{id: string, data: object}>>} */
    async get() {
      const snap = await this._build().get();
      const rows = snap.docs.map((d) => ({id: d.id, data: d.data() || {}}));
      if (o.onRead) o.onRead(this._template, rows);
      return rows;
    }
  }

  return {
    query(template, params) {
      const r = resolve(template, params);
      return new Query(template, r.path, r.allowed, []);
    },
    /** Whole config document (switches only), or {} when missing. */
    async config(docPath) {
      if (fields.CONFIG_DOCS.indexOf(docPath) < 0) {
        throw guardError(`not a config doc: ${docPath}`);
      }
      const snap = await db.doc(docPath).get();
      const data = snap.exists ? (snap.data() || {}) : {};
      if (o.onRead) o.onRead(docPath, [{id: snap.id, data}]);
      return data;
    },
  };
}

module.exports = {guardedDb, assertNotDenied};
