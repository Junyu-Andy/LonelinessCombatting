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
  Future<void> compileAtSessionEnd({
    required String uid,
    required String agentId,
  }) async {
    final snapshot = await agentContext.read(uid: uid, agentId: agentId);
    final buffer = snapshot.shortTermBuffer;
    if (buffer.isEmpty) {
      // Nothing retained this session (guest mode or retention OFF) — keep
      // the prior summary untouched.
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

    final response = await llm.send(
      moduleId: 'rolling_summary_fold',
      systemPrompt: _foldSystemPrompt,
      agentId: agentId,
      history: const [],
      userInput: userInput.toString(),
      uid: uid,
    );

    // Only overwrite on a real, non-short-circuited result. On failure we
    // keep the prior summary (non-destructive) but still clear the buffer so
    // the next session starts clean rather than re-folding stale turns.
    final folded = response.text.trim();
    if (!response.shortCircuited && folded.isNotEmpty) {
      await agentContext.writeRollingSummary(
        uid: uid,
        agentId: agentId,
        summary: _truncate(folded),
      );
    }
    await agentContext.discardShortTermBuffer(uid: uid, agentId: agentId);
  }

  static String _truncate(String s) {
    final runes = s.runes.toList();
    if (runes.length <= _maxChars) return s;
    return String.fromCharCodes(runes.take(_maxChars));
  }
}
