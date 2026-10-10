/// Decision 0023 — pick, remember and log one Arm B template reply.
library;

import 'dart:async';

import '../../analytics/data/analytics_service.dart';
import 'rule_reply_history_store.dart';
import 'rule_reply_picker.dart';
import 'rule_reply_pool.dart';

class RuleReplyService {
  final RuleReplyHistoryStore store;
  const RuleReplyService({required this.store});

  /// The next reply for [agentId] × [mood] (1..5, or null when no mood was
  /// picked).  [grief] (reminiscence text that hit `moderate_review`)
  /// ignores the mood and uses the Z5 group (T33).  [theme] is logged
  /// only; since T33 the pool has no theme dimension.  Records the reply
  /// in the user's recent list and logs `rule_template_reply`.  Null only
  /// when the sub-pool is empty.
  Future<RuleReplyEntry?> next({
    required String? uid,
    required String agentId,
    required String moduleId,
    required String theme,
    required int? mood,
    bool grief = false,
    AnalyticsService? analytics,
  }) async {
    final band = grief ? RuleReplyPool.bandGrief : RuleReplyPool.bandFor(mood);
    final pool = RuleReplyPool.subPool(agent: agentId, band: band);
    final recent = await store.recent(uid: uid, agentId: agentId);
    final entry = RuleReplyPicker.pick(pool, recent);
    if (entry == null) return null;
    unawaited(
      store.save(
        uid: uid,
        agentId: agentId,
        recent: RuleReplyPicker.remember(recent, entry.id),
      ),
    );
    unawaited(
      analytics?.logEvent('rule_template_reply', {
            'agent_id': agentId,
            'module_id': moduleId,
            'template_id': entry.id,
            'pool_version': RuleReplyPool.version,
            'theme': theme,
            'mood_band': band,
            if (mood != null) 'mood': mood,
          }) ??
          Future<void>.value(),
    );
    return entry;
  }
}
