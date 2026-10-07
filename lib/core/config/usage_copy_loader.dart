/// Reads `app_config/usage_copy` into [UsageCopy.current] (T20).
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'usage_copy.dart';

class UsageCopyLoader {
  UsageCopyLoader._();

  /// Never throws; on any failure the copy is empty, so every site
  /// keeps today's text.
  static Future<UsageCopy> load({bool available = true}) async {
    if (!available) return UsageCopy.current = const UsageCopy();
    try {
      final snap = await FirebaseFirestore.instance
          .doc(UsageCopy.remotePath)
          .get()
          .timeout(const Duration(seconds: 3));
      UsageCopy.current = UsageCopy.fromMap(snap.data() ?? const {});
    } catch (e) {
      if (kDebugMode) debugPrint('[UsageCopy] load failed: $e');
      UsageCopy.current = const UsageCopy();
    }
    return UsageCopy.current;
  }
}
