/// Runtime feature flags read from Firestore (decision 0019, SPEC:C18).
///
/// Unlike [FeatureFlags] (compile-time dart-defines), these live in the
/// `app_config/feature_flags` document so the research team can switch
/// them from the console without a new build, and the Cloud Functions
/// read the same document (functions/feature_flags.js) — turning a flag
/// off closes both the app entry point and the server endpoint.
///
/// Every flag is OFF unless its field is literally `true`.  A missing
/// document, a failed read or any other value keeps it off.
///
///   - [webSearchEnabled]      — Tung Tung "搜一搜" (Hybrid arm only).
///   - [voiceInputEnabled]     — mic button on every input page, both
///                               arms.  **Important feature: switch back
///                               on once HREC approves the STT amendment.**
///   - [searchOffReplyEnabled] — while search is off, Tung Tung answers
///                               search-type questions with one fixed
///                               line ([TungTungSearchIntent]).  The line
///                               is a placeholder until the research team
///                               signs it off.
///   - [memoryLayersNoticeEnabled] — T31 (decision 0034): the S7 notice
///                               about shared / private memory at the top
///                               of 「我記得嘅嘢」.  Switch on together with
///                               `meta/memory_config.layersEnabled`.
///
/// Call [RemoteFeatureFlags.load] once at startup; read via [current].
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class RemoteFeatureFlags {
  const RemoteFeatureFlags({
    this.webSearchEnabled = false,
    this.voiceInputEnabled = false,
    this.searchOffReplyEnabled = false,
    this.memoryLayersNoticeEnabled = false,
  });

  final bool webSearchEnabled;
  final bool voiceInputEnabled;
  final bool searchOffReplyEnabled;
  final bool memoryLayersNoticeEnabled;

  static RemoteFeatureFlags _current = const RemoteFeatureFlags();

  /// The active flags (all off until [load] reads the document).
  static RemoteFeatureFlags get current => _current;

  /// Test / tooling hook.
  @visibleForTesting
  static set current(RemoteFeatureFlags value) => _current = value;

  /// Firestore document holding the flags.  Read-only for clients.
  static const String remotePath = 'app_config/feature_flags';

  /// Read the flags.  Never throws; on any failure every flag is off.
  static Future<RemoteFeatureFlags> load({bool available = true}) async {
    if (!available) return _current = const RemoteFeatureFlags();
    try {
      final snap = await FirebaseFirestore.instance
          .doc(remotePath)
          .get()
          .timeout(const Duration(seconds: 3));
      _current = fromMap(snap.data() ?? const {});
    } catch (e) {
      if (kDebugMode) debugPrint('[RemoteFeatureFlags] load failed: $e');
      _current = const RemoteFeatureFlags();
    }
    return _current;
  }

  /// Pure parse used by [load] and tests: only `true` turns a flag on.
  static RemoteFeatureFlags fromMap(Map<String, dynamic> map) =>
      RemoteFeatureFlags(
        webSearchEnabled: map['webSearchEnabled'] == true,
        voiceInputEnabled: map['voiceInputEnabled'] == true,
        searchOffReplyEnabled: map['searchOffReplyEnabled'] == true,
        memoryLayersNoticeEnabled: map['memoryLayersNoticeEnabled'] == true,
      );
}
