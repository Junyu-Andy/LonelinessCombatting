/// T25 (registry C14) — when a Brief PR invitation is made, shown, answered,
/// skipped or expired.  Pure decision logic over a [BriefPrStore]; no
/// widgets, no Firestore types, an injectable clock.  Both arms run exactly
/// this code (the rule arm never calls an LLM anywhere in here).
///
/// Rules (dev-tasks-1009b T25 §5–§7, 1010 §三, 1010b §二):
///   - invite only after a VALID session (never mid-chat, no manual entry);
///   - at most `briefPrDailyCapPerAgent` invitations per companion per local
///     day; over the cap: no record, the session row gets
///     `briefPrSkippedByCap: true`;
///   - a session that ended in crisis (or any valid session while a crisis
///     is being handled) gets a `due_not_invited` record with the reason;
///   - ended by close / back / switch → list-page card (S10a); ended by
///     timeout / recovered → catch-up card on the next open (S10b);
///   - an invitation expires `briefPrCatchUpExpiryHours` (2 h) after the
///     session's last complete reply (`expired`, `everShown` kept);
///   - 「今次唔評」 = `skipped`; all four items = `completed`; some items then
///     abandoned = `partially_completed`;
///   - one record per session id, so a duplicate submission is impossible.
library;

import '../../../core/session/chat_session_recorder.dart';
import 'brief_pr_record.dart';
import 'brief_pr_store.dart';

/// Outcome of [BriefPrScheduler.onSessionEnded].
enum BriefPrDecision {
  /// Switch off: the caller runs the pre-T25 popup path.
  legacy,

  /// Not a valid session (or no reply at all): nothing recorded.
  notValid,

  /// A record for this session already exists (retry / double call).
  alreadyRecorded,

  /// Valid, but the daily cap for this companion is used up.  No record;
  /// the session row is marked.
  skippedByCap,

  /// Valid, but a crisis was being handled: `due_not_invited` record.
  dueNotInvited,

  /// Invitation recorded (pending); a card will show.
  invited,
}

class BriefPrScheduler {
  BriefPrScheduler({
    required this.store,
    required this.rules,
    DateTime Function()? clock,
    DateTime? processStartedAt,
  })  : _clock = clock ?? DateTime.now,
        processStartedAt = processStartedAt ?? (clock ?? DateTime.now)();

  final BriefPrStore store;
  final SessionRules rules;
  final DateTime Function() _clock;

  /// Start of this App process.  An invitation made before it (the user
  /// killed the App before seeing the list page) is shown as the catch-up
  /// card (S10b) even if the session ended by close / back / switch.
  final DateTime processStartedAt;

  DateTime get now => _clock();

  /// Called once per ended session (from the chat page's end-of-session
  /// flow, the rule arm's submission flow, or the app-start sweep).
  Future<BriefPrDecision> onSessionEnded(
    SessionEndSummary s, {
    required String agentDisplayName,
    String? arm,
    bool crisisInProgress = false,
  }) async {
    if (!rules.v2) return BriefPrDecision.legacy;
    if (!s.isValid) return BriefPrDecision.notValid;
    final existing = await store.get(s.uid, s.sessionId);
    if (existing != null) return BriefPrDecision.alreadyRecorded;

    final t = now;
    final dayKey = BriefPrRecord.dayKey(t);
    final invitedBefore = await store.countInvited(s.uid, s.agentId, dayKey);
    final base = BriefPrRecord(
      uid: s.uid,
      sessionId: s.sessionId,
      agentId: s.agentId,
      agentDisplayName: agentDisplayName,
      sessionType: s.sessionType.code,
      endReason: s.endReason,
      sessionEndedAt: s.endedAt,
      lastReplyAt: s.lastReplyAt,
      arm: arm,
    );

    if (s.endReason == SessionEndReason.crisis || crisisInProgress) {
      await store.put(base.copyWith(
        finalStatus: BriefPrStatus.dueNotInvited,
        dueNotInvitedReason: BriefPrDueNotInvitedReason.crisis,
      ));
      await store.patchSession(s.uid, s.sessionId, {
        'briefPrInvitedTodayAlready': invitedBefore > 0,
        'briefPrSkippedByCap': false,
        'briefPrStatus': BriefPrStatus.dueNotInvited,
      });
      return BriefPrDecision.dueNotInvited;
    }

    if (invitedBefore >= rules.briefPrDailyCapPerAgent) {
      await store.patchSession(s.uid, s.sessionId, {
        'briefPrInvitedTodayAlready': true,
        'briefPrSkippedByCap': true,
      });
      return BriefPrDecision.skippedByCap;
    }

    await store.put(base.copyWith(
      invitedAt: t,
      invitedDayKey: dayKey,
      inviteChannel: SessionEndReason.isCatchUp(s.endReason)
          ? BriefPrInviteChannel.catchUp
          : BriefPrInviteChannel.listPage,
    ));
    await store.patchSession(s.uid, s.sessionId, {
      'briefPrInvitedTodayAlready': invitedBefore > 0,
      'briefPrSkippedByCap': false,
      'briefPrInvited': true,
    });
    return BriefPrDecision.invited;
  }

  /// Whether a pending record has passed its expiry at [at].  Strictly
  /// "more than" the configured hours: 1:59 and 2:00 still show, 2:01 is
  /// expired.
  bool isExpired(BriefPrRecord r, DateTime at) =>
      at.difference(r.expiryAnchor) > rules.catchUpExpiry;

  /// Marks every stale pending record `expired` and returns the one card
  /// to show now (the most recently ended session), or null.
  Future<BriefPrRecord?> nextCard(String uid) async {
    if (!rules.v2) return null;
    final t = now;
    final pending = await store.pending(uid);
    BriefPrRecord? best;
    for (final r in pending) {
      if (r.invitedAt == null) continue; // due_not_invited never pends
      if (isExpired(r, t)) {
        await store.put(r.copyWith(finalStatus: BriefPrStatus.expired));
        continue;
      }
      if (best == null || r.sessionEndedAt.isAfter(best.sessionEndedAt)) {
        best = r;
      }
    }
    return best;
  }

  /// The channel a card is shown through: catch-up (S10b) when the session
  /// ended by timeout / recovery, or when the invitation predates this App
  /// process (the participant left before seeing the list page).
  String channelFor(BriefPrRecord r) {
    if (r.inviteChannel == BriefPrInviteChannel.catchUp) {
      return BriefPrInviteChannel.catchUp;
    }
    final invited = r.invitedAt;
    if (invited != null && invited.isBefore(processStartedAt)) {
      return BriefPrInviteChannel.catchUp;
    }
    return BriefPrInviteChannel.listPage;
  }

  /// The card is on screen.  Records `everShown`, the first `shownAt` and
  /// the channel actually used.
  Future<BriefPrRecord> markShown(BriefPrRecord r) async {
    final updated = r.copyWith(
      everShown: true,
      shownAt: r.shownAt ?? now,
      inviteChannel: channelFor(r),
    );
    if (updated.everShown != r.everShown ||
        updated.shownAt != r.shownAt ||
        updated.inviteChannel != r.inviteChannel) {
      await store.put(updated);
    }
    return updated;
  }

  /// 「今次唔評」, or the questionnaire abandoned before any answer.
  Future<bool> skip(BriefPrRecord r) => _finish(r, BriefPrStatus.skipped, {});

  /// Submit / abandon with answers.  All four → `completed`; some →
  /// `partially_completed`; none → `skipped`.  Returns false when the record
  /// is already final (duplicate submission): nothing is written.
  Future<bool> submit(BriefPrRecord r, Map<String, int?> answers) {
    final items = <String, int>{
      for (final k in briefPrItemKeys)
        if (answers[k] != null) k: answers[k]!,
    };
    final status = items.isEmpty
        ? BriefPrStatus.skipped
        : items.length == briefPrItemKeys.length
            ? BriefPrStatus.completed
            : BriefPrStatus.partiallyCompleted;
    return _finish(r, status, items);
  }

  Future<bool> _finish(
      BriefPrRecord r, String status, Map<String, int> items) async {
    final current = await store.get(r.uid, r.sessionId) ?? r;
    if (!current.isPending) return false;
    await store.put(current.copyWith(
      finalStatus: status,
      ratedAt: now,
      everShown: true,
      items: items,
    ));
    return true;
  }

  // -- S10b time phrase ------------------------------------------------------

  /// The one approved word (dev-tasks-1014e §2.8, 10/15): every catch-up
  /// card says 「頭先」, whatever the gap.  The three time-of-day forms
  /// (今朝 / 尋晚 / 星期X 下晝) and the 【占位】 fallback of T25 are retired,
  /// so no card is ever held back for a missing phrase.
  static const timePhraseFixed = '頭先';

  static String timePhrase(DateTime endedAt, DateTime now) => timePhraseFixed;
}
