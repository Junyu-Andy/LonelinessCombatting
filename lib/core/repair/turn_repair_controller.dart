/// B.9 — 唔啱意思 (repair) controller (Sprint 2.5).
///
/// Policy:
///   • On first thumbs-down for a turn: re-send the same user input to the
///     LLM with `regenerate=true`.  The CF treats it as a fresh call.
///   • On subsequent thumbs-down for the SAME turn: advance a rule-based
///     template index — no further LLM calls (Arm B fallback semantics).
///   • Debounce 2s — rapid taps must not stack 5 LLM calls.
///   • Link `originalTurnRef → repairTurnRef` on the new turn so the
///     researcher dashboard (Sprint 3 B.13) can pair them.
///
/// This class is transport-only — UI lives in `repair_button.dart`.
library;

import 'dart:async';

class TurnRepairController {
  TurnRepairController({Duration? debounce})
      : _debounce = debounce ?? const Duration(seconds: 2);

  final Duration _debounce;

  /// Tracks (turnKey → click count) so subsequent taps on the same turn
  /// advance the template index rather than re-call the LLM.
  final Map<String, int> _clicks = {};

  /// Tracks last click timestamp per turn for debouncing.
  final Map<String, DateTime> _lastClickAt = {};

  /// Decide what to do for this thumbs-down click.  Returns null when the
  /// click should be ignored (debounce).
  RepairAction? onThumbsDown(String turnKey) {
    final now = DateTime.now();
    final last = _lastClickAt[turnKey];
    if (last != null && now.difference(last) < _debounce) {
      return null; // debounced
    }
    _lastClickAt[turnKey] = now;
    final priorCount = _clicks[turnKey] ?? 0;
    _clicks[turnKey] = priorCount + 1;
    if (priorCount == 0) {
      return const RepairAction.llmRegenerate();
    }
    // Subsequent click — advance template index.  Index = priorCount-1
    // so the second click yields template index 0, third click index 1.
    return RepairAction.templateAdvance(index: priorCount);
  }

  int clicksForTest(String turnKey) => _clicks[turnKey] ?? 0;

  void reset(String turnKey) {
    _clicks.remove(turnKey);
    _lastClickAt.remove(turnKey);
  }
}

class RepairAction {
  /// 'llm_regenerate' or 'template_advance'.
  final String kind;
  final int templateIndex;

  const RepairAction._(this.kind, this.templateIndex);
  const RepairAction.llmRegenerate()
      : kind = 'llm_regenerate',
        templateIndex = -1;
  const RepairAction.templateAdvance({required int index})
      : kind = 'template_advance',
        templateIndex = index;

  bool get isLlmRegenerate => kind == 'llm_regenerate';
  bool get isTemplateAdvance => kind == 'template_advance';
}
