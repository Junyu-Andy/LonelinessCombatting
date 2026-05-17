import 'package:cloud_firestore/cloud_firestore.dart';

import '../safety/distress_detector.dart';
import 'memory_store.dart';

/// One eligible cross-module callback (e.g. M2 LLM can lightly reference
/// last week's M3 reminiscence). The string injected into the system
/// prompt is built via [toSystemPromptInjection]; analytics + budget
/// bookkeeping is done by the service that produced this object.
class CrossModuleCallback {
  /// e.g. `m3_reminiscence_w2`
  final String sourceModuleId;

  /// Coarse source name reported in analytics ('m3', 'm5', …).
  final String sourceFamily;

  /// First sentence of the source summary, suitable for inline injection.
  final String summarySnippet;

  /// Full sanitized summary in case the prompt template wants more.
  final String fullSummary;

  const CrossModuleCallback({
    required this.sourceModuleId,
    required this.sourceFamily,
    required this.summarySnippet,
    required this.fullSummary,
  });

  String toSystemPromptInjection({required bool isEn}) {
    if (isEn) {
      return '\nThe user previously shared with you (sanitized, user-reviewed): '
          '"$summarySnippet"\n'
          'If — and only if — a natural opening arises in their next reply, '
          'you may briefly callback to this once. Do not list. Do not force.';
    }
    return '\n（用戶之前同你分享過嘅，已經由佢自己睇過/編輯過）：「$summarySnippet」\n'
        '只有當對方接住嘅內容自然引到呢度，先輕輕提一次。唔好列出嚟、唔好強行帶入。';
  }
}

/// Service that decides whether a *target* module (e.g. M2 check-in) is
/// allowed to reference content from a *source* module (e.g. M3
/// reminiscence) on this turn.
///
/// Why a budget: the dissertation deliberately avoids saturating the
/// participant with "I remember you said…" prompts; a single soft
/// callback per ISO-week per (target,source) pair preserves the felt
/// continuity without becoming uncanny. The Firestore doc at
/// `users/{uid}/cross_module_callbacks/{target}_{weekKey}` records the
/// budget hit; absence = unused this week.
///
/// Why summaries (not transcripts) are readable even when transcript
/// consent is off: the entries written via [MemoryStore.writeSummary]
/// are user-reviewed / user-editable summaries, not raw transcript.
/// Spec §M3 + §Consent describes this carve-out. Raw transcripts live
/// in a separate subcollection and are NOT touched here.
class CrossModuleMemoryService {
  CrossModuleMemoryService({
    required this.memory,
    required this.firestoreAvailable,
  });

  final MemoryStore memory;
  final bool firestoreAvailable;

  /// Resolve an eligible callback for [forModuleFamily] (e.g. `'m2'`).
  ///
  /// [candidateSourceModuleIds] are full module IDs in priority order
  /// (e.g. `['m3_reminiscence_w4', 'm3_reminiscence_w3', …]`). The first
  /// one with a non-empty summary wins.
  ///
  /// Returns null if any of the gating rules fires:
  ///   - Current turn distress is moderate or acute (never callback in a
  ///     distress turn — risks compounding affect).
  ///   - This (target, ISO-week) pair already used its budget.
  ///   - No candidate has a stored summary.
  Future<CrossModuleCallback?> getEligibleCallback({
    required String uid,
    required String forModuleFamily,
    required List<String> candidateSourceModuleIds,
    required DistressLevel currentTurnDistress,
    DateTime? now,
  }) async {
    if (!firestoreAvailable) return null;
    if (currentTurnDistress == DistressLevel.moderate ||
        currentTurnDistress == DistressLevel.acute) {
      return null;
    }
    final weekKey = _isoWeekKey(now ?? DateTime.now());
    final budgetDocRef = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('cross_module_callbacks')
        .doc('${forModuleFamily}_$weekKey');
    final snap = await budgetDocRef.get();
    if (snap.exists) return null;

    for (final moduleId in candidateSourceModuleIds) {
      final entries = await memory.recent(
        uid: uid,
        moduleId: moduleId,
        limit: 1,
      );
      if (entries.isEmpty) continue;
      final summary = entries.first.summary.trim();
      if (summary.isEmpty) continue;
      return CrossModuleCallback(
        sourceModuleId: moduleId,
        sourceFamily: _sourceFamily(moduleId),
        summarySnippet: _firstSentence(summary),
        fullSummary: summary,
      );
    }
    return null;
  }

  /// Mark the callback budget for this (target, ISO-week) as spent.
  ///
  /// Called whether or not the LLM actually wove the callback into its
  /// reply (conservative — even mentioning it in the system prompt
  /// counts as having had the chance).
  Future<void> markUsed({
    required String uid,
    required String forModuleFamily,
    required CrossModuleCallback callback,
    DateTime? now,
  }) async {
    if (!firestoreAvailable) return;
    final weekKey = _isoWeekKey(now ?? DateTime.now());
    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('cross_module_callbacks')
        .doc('${forModuleFamily}_$weekKey')
        .set({
      'source_module_id': callback.sourceModuleId,
      'source_family': callback.sourceFamily,
      'used_at': FieldValue.serverTimestamp(),
    });
  }

  static String _isoWeekKey(DateTime when) {
    // ISO 8601 week-of-year, Monday-start.
    final thursday =
        when.subtract(Duration(days: when.weekday - DateTime.thursday));
    final yearStart = DateTime(thursday.year, 1, 1);
    final dayOfYear = thursday.difference(yearStart).inDays;
    final week = (dayOfYear / 7).floor() + 1;
    return '${thursday.year}_W${week.toString().padLeft(2, '0')}';
  }

  static String _sourceFamily(String moduleId) {
    // m3_reminiscence_w2 → m3; m5_reflection → m5; etc.
    final dash = moduleId.indexOf('_');
    return dash <= 0 ? moduleId : moduleId.substring(0, dash);
  }

  static String _firstSentence(String text) {
    final match = RegExp(r'^[^。！？.!?\n]+[。！？.!?]').firstMatch(text);
    if (match != null) return match.group(0)!.trim();
    return text.length > 80 ? '${text.substring(0, 80)}…' : text;
  }
}
