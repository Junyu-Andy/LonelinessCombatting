/// T35 开工方式 (4) (handover 1021-W8) — which App build each person runs.
///
/// Every time the App opens with a signed-in account it writes one field,
/// `users/{uid}.appBuild`:
///   version   [BuildInfo.appVersion]  (pubspec, e.g. 1.0.0)
///   build     [BuildInfo.buildNumber] (pubspec, e.g. 3)
///   w8        true — this build has the W8 questionnaire page (T35).
///             Builds from before T35 never write the field at all, so
///             "no appBuild" = an old build without the W8 page.
///   platform  android / ios / …
///   seenAt    server time of the report
/// The research lead sees it in the operations dashboard's person row
/// (App 版本) and in `tool/w8_dates.js`, and can find before study day 56
/// who still has to get the new build.  The elder sees nothing; both arms
/// the same; no switch.  firestore.rules accepts only exactly this shape
/// with the server time.  An account with no users/{uid} document (staff)
/// gets nothing: the write is an update, never a create.
///
/// Note: until the release raises `version:` in pubspec.yaml, every build
/// says 1.0.0 (3); `w8` is what tells the builds apart.
library;

import 'package:cloud_firestore/cloud_firestore.dart';

import 'build_info.dart';

class AppBuildRecorder {
  AppBuildRecorder._();

  /// This build has the W8 questionnaire (lib/features/w8/).
  static const hasW8 = true;

  /// The field's value.  [seenAt] is the server time in the App
  /// ([FieldValue.serverTimestamp]); tests pass a marker.
  static Map<String, Object> value({
    required String platform,
    required Object seenAt,
  }) =>
      {
        'version': BuildInfo.appVersion,
        'build': BuildInfo.buildNumber,
        'w8': hasW8,
        if (platform.isNotEmpty)
          'platform':
              platform.length > 16 ? platform.substring(0, 16) : platform,
        'seenAt': seenAt,
      };

  /// Report this build for [uid] (once per App open).  Never throws,
  /// never blocks: a failure (offline, no user document) is ignored.
  static Future<void> record(
    String uid, {
    required String platform,
    Future<void> Function(String uid, Map<String, Object> data)? write,
  }) async {
    final data = {
      'appBuild':
          value(platform: platform, seenAt: FieldValue.serverTimestamp()),
    };
    try {
      if (write != null) {
        await write(uid, data);
      } else {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .update(data);
      }
    } catch (_) {}
  }
}
