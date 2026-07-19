/// Session-end rolling-summary fold (Demo Sprint Plan §1C + Appendix A).
///
/// This is the piece that "powers on" cross-session memory: at the end of a
/// session it folds the short-term buffer (the verbatim turns retained this
/// session) together with the prior rolling summary into a single ≤500-char
/// Cantonese summary, writes it back to `agent_contexts/{agentId}`, then
/// discards the verbatim buffer.
///
/// Cost model (Appendix A): exactly one extra LLM call per session, only
/// when there is buffered content to fold. No call in guest mode, no call
/// when the user opted out of transcript retention (the buffer is empty in
/// that case), and no destructive write when the fold fails — the prior
/// summary is preserved.
library;

import '../llm/llm_gateway.dart';
import 'agent_context_service.dart';

class RollingSummaryCompiler {
  RollingSummaryCompiler({
    required this.agentContext,
    required this.llm,
  });

  final AgentContextService agentContext;
  final LlmGateway llm;

  /// Hard cap from Appendix A. Characters (runes), not words — the summary
  /// is Cantonese.
  static const int _maxChars = 500;

  /// The fold instruction (Appendix A "fold" prompt draft).
  static const String _foldSystemPrompt = '''
你要把一位用戶同某個 companion 嘅過往傾偈，更新成一段簡短摘要。
輸入：舊摘要(≤500字) + 今次 session 嘅對話。
要求：
- 輸出一段 ≤500 字粵語摘要，覆蓋：傾過咩 / 而家狀態同心情走勢 / 唔好提嘅嘢 / 仲未傾完嘅線索。
- 保留仍然相關嘅，唔好無限疊加舊嘢，只記真實講過嘅，唔好捏造。
- 唔好放電話／地址／身份證等 PII。
只輸出摘要本身。''';

  /// Fold the current session for ([uid], [agentId]) into the rolling
  /// summary and clear the short-term buffer. Safe to call unconditionally
  /// at session end — it no-ops when there's nothing to fold.
  ///
  /// [retentionOn] is the per-agent transcript-retention consent; pass it so
  /// the T5 fold-status can distinguish "consent off" from "empty session".
  Future<void> compileAtSessionEnd({
    required String uid,
    required String agentId,
    bool retentionOn = true,
  }) async {
    // Callers fire-and-forget this — a Firestore read/write failure in
    // here must never surface as an unhandled async exception.
    try {
      await _compile(uid: uid, agentId: agentId, retentionOn: retentionOn);
    } catch (_) {
      // Best-effort: prior summary is untouched; the buffer (if any)
      // simply re-folds at the next session end.
    }
  }

  Future<void> _compile({
    required String uid,
    required String agentId,
    required bool retentionOn,
  }) async {
    // T5 — record the outcome so it's visible in the console.
    if (!retentionOn) {
      await agentContext.writeFoldStatus(
        uid: uid, agentId: agentId, status: 'skipped_consent_off');
      return;
    }

    final snapshot = await agentContext.read(uid: uid, agentId: agentId);
    final buffer = snapshot.shortTermBuffer;
    if (buffer.isEmpty) {
      // Retention is on but nothing was buffered (e.g. opened the room but
      // didn't talk). Keep the prior summary untouched.
      await agentContext.writeFoldStatus(
        uid: uid, agentId: agentId, status: 'skipped_empty');
      return;
    }

    final transcript = buffer
        .map((t) => '${t.fromUser ? '用戶' : 'companion'}：${t.text}')
        .join('\n');
    final oldSummary = snapshot.rollingSummary.trim();
    final userInput = StringBuffer()
      ..writeln('[舊摘要]')
      ..writeln(oldSummary.isEmpty ? '（暫時未有）' : oldSummary)
      ..writeln()
      ..writeln('[今次對話]')
      ..write(transcript);

    String status;
    String? error;
    try {
      final response = await llm.send(
        moduleId: 'rolling_summary_fold',
        systemPrompt: _foldSystemPrompt,
        agentId: agentId,
        history: const [],
        userInput: userInput.toString(),
        uid: uid,
        // Every turn in this transcript was already distress-scanned live;
        // re-scanning here double-fired safety alerts (grief vocabulary is
        // routine for this population) and an acute term anywhere in the
        // session short-circuited the fold, losing that session's memory.
        skipSafetyScan: true,
      );

      final folded = response.text.trim();
      if (response.shortCircuited) {
        // Distress short-circuit on the transcript — guardrail suppressed
        // the fold. Prior summary preserved.
        status = 'suppressed_distress';
      } else if (folded.isEmpty) {
        // LLM returned nothing (no API key, timeout, upstream error).
        status = 'failed';
        error = 'empty_llm_response';
      } else {
        await agentContext.writeRollingSummary(
          uid: uid,
          agentId: agentId,
          summary: _truncate(folded),
        );
        status = 'ok';
      }
    } catch (e) {
      status = 'failed';
      error = e.toString();
    }

    await agentContext.writeFoldStatus(
      uid: uid, agentId: agentId, status: status, error: error);
    // Clear the buffer regardless: non-destructive to the summary, and stops
    // a failed fold from re-folding stale turns next session.
    await agentContext.discardShortTermBuffer(uid: uid, agentId: agentId);
  }

  static String _truncate(String s) {
    final runes = s.runes.toList();
    if (runes.length <= _maxChars) return s;
    return String.fromCharCodes(runes.take(_maxChars));
  }
}
