/// 1020e 一.(9) — which home page a session was started from, for 1020
/// §1 (4) (expired Brief PR invitations counted by start page).
///
/// Page 1 「睇今日」 and page 2 「搵人傾」 of the two-page layout
/// (`homeLayoutV2Enabled`) wrap every navigation that can lead to a
/// session in [during] (via `HomeSurfaceScope.push`).  While that page
/// is open, every session that starts — a companion chat
/// ([ChatSessionRecorder]) or a tool page (`ToolSessionScope`) — copies
/// [current] into `users/{uid}/sessions/{id}.entrySurface`: `page1`,
/// `page2`, or null when it was not reached from a home page (a push,
/// the old layout, …).  A session reached by a hand-off inside that visit
/// (e.g. a referral card) keeps the page the visit started from.
///
/// Process-wide, in memory only; nothing about the elder is stored here.
library;

import 'package:flutter/foundation.dart';

class SessionEntrySurface {
  SessionEntrySurface._();

  static const String page1 = 'page1';
  static const String page2 = 'page2';

  static String? _current;

  /// The home page whose navigation is open now, or null.
  static String? get current => _current;

  /// Runs [open] (a push from a home page; completes when that page is
  /// popped) with [surface] marked; restores the previous mark after.
  static Future<T?> during<T>(
      String? surface, Future<T?> Function() open) async {
    if (surface == null) return open();
    final previous = _current;
    _current = surface;
    try {
      return await open();
    } finally {
      _current = previous;
    }
  }

  @visibleForTesting
  static void resetForTest() => _current = null;
}
