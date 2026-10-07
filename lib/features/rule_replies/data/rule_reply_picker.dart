/// Decision 0023 — deterministic template choice for the Arm B check-in /
/// reminiscence replies.  Pure function, no I/O, no LLM.
library;

import 'rule_reply_pool.dart';

class RuleReplyPicker {
  const RuleReplyPicker._();

  /// Pick from [subPool] given [recent] template ids (oldest first, most
  /// recent last).  Rule: the first entry not among the last [window]
  /// ids; if all were used, the one whose last use is the oldest.
  /// Returns null only for an empty [subPool].
  static RuleReplyEntry? pick(
    List<RuleReplyEntry> subPool,
    List<String> recent, {
    int window = RuleReplyPool.recentWindow,
  }) {
    if (subPool.isEmpty) return null;
    final start = recent.length > window ? recent.length - window : 0;
    final blocked = recent.sublist(start).toSet();
    for (final e in subPool) {
      if (!blocked.contains(e.id)) return e;
    }
    RuleReplyEntry best = subPool.first;
    var bestLastUse = recent.lastIndexOf(best.id);
    for (final e in subPool.skip(1)) {
      final lastUse = recent.lastIndexOf(e.id);
      if (lastUse < bestLastUse) {
        best = e;
        bestLastUse = lastUse;
      }
    }
    return best;
  }

  /// [recent] with [id] appended, trimmed to the last [keep] ids.
  static List<String> remember(
    List<String> recent,
    String id, {
    int keep = RuleReplyPool.recentWindow,
  }) {
    final next = [...recent, id];
    return next.length > keep ? next.sublist(next.length - keep) : next;
  }
}
