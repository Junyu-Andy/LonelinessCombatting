/// Researcher dashboard (Dev Req §11.1).
///
/// Phase A admin-only surface that shows participant engagement,
/// pending distress flags, transcript audit queue, per-agent PPR
/// aggregates, and cross-referral statistics.
///
/// Gated by the Firebase custom claim `role: researcher`. The auth
/// check is intentionally strict — if the claim is missing the page
/// renders an "access denied" state rather than degraded data.
/// Provision the claim via Firebase Admin SDK (a one-off script on
/// the researcher account) before the Phase A pilot starts.
library;

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../auth/presentation/auth_service_scope.dart';

class ResearcherDashboardPage extends StatefulWidget {
  const ResearcherDashboardPage({super.key});

  @override
  State<ResearcherDashboardPage> createState() =>
      _ResearcherDashboardPageState();
}

class _ResearcherDashboardPageState extends State<ResearcherDashboardPage> {
  Future<bool>? _authCheck;

  @override
  void initState() {
    super.initState();
    _authCheck = _checkResearcherClaim();
  }

  Future<bool> _checkResearcherClaim() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    try {
      final token = await user.getIdTokenResult(true);
      final role = token.claims?['role'];
      return role == 'researcher';
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = AuthServiceScope.of(context);
    final isEn = Localizations.localeOf(context).languageCode == 'en';

    if (!auth.available) {
      return Scaffold(
        appBar: AppBar(title: Text(isEn ? 'Researcher' : '研究員')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              isEn
                  ? 'Firebase not configured — dashboard unavailable.'
                  : 'Firebase 未配置 —— 儀錶板未可用。',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return FutureBuilder<bool>(
      future: _authCheck,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const _DashboardScaffold(
              title: 'Researcher',
              body: Center(child: CircularProgressIndicator()));
        }
        if (snap.data != true) {
          return _DashboardScaffold(
            title: isEn ? 'Researcher' : '研究員',
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  isEn
                      ? 'Access denied. This dashboard requires the '
                          'researcher role. Ask the admin to provision it.'
                      : '冇權限。呢個儀錶板需要 researcher 角色，請聯絡管理員。',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }
        return _DashboardScaffold(
          title: isEn ? 'Researcher dashboard' : '研究員儀錶板',
          body: _DashboardBody(isEn: isEn),
        );
      },
    );
  }
}

class _DashboardScaffold extends StatelessWidget {
  final String title;
  final Widget body;
  const _DashboardScaffold({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(child: body),
    );
  }
}

class _DashboardBody extends StatelessWidget {
  final bool isEn;
  const _DashboardBody({required this.isEn});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 60),
      children: [
        _SectionHeader(
            label: isEn ? 'Pending distress flags' : '未處理嘅 distress flags'),
        const _DistressFlagsList(),
        const SizedBox(height: 24),
        _SectionHeader(label: isEn ? 'Engagement' : '參與度'),
        const _EngagementSummary(),
        const SizedBox(height: 24),
        _SectionHeader(label: isEn ? 'Transcript audit queue' : '對話審計隊列'),
        const _TranscriptAuditList(),
        const SizedBox(height: 24),
        _SectionHeader(label: isEn ? 'Cross-referral' : '跨 agent 轉介'),
        const _CrossReferralStats(),
        const SizedBox(height: 24),
        _SectionHeader(label: isEn ? 'PPR aggregates' : 'PPR 總體分布'),
        const _PprAggregates(),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Text(label, style: Theme.of(context).textTheme.titleLarge),
    );
  }
}

class _DistressFlagsList extends StatelessWidget {
  const _DistressFlagsList();

  @override
  Widget build(BuildContext context) {
    // collectionGroup pulls every users/*/shared_context/current doc's
    // safetyFlags array. We can't direct-query an array element, so
    // dashboard ops read the whole shared_context doc; for very large
    // cohorts this should move to a server-side rollup.
    final stream = FirebaseFirestore.instance
        .collectionGroup('shared_context')
        .snapshots();
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const _Loading();
        }
        final entries = <_FlagRow>[];
        for (final doc in snap.data!.docs) {
          final uid = doc.reference.parent.parent?.id ?? '';
          final flags = doc.data()['safetyFlags'];
          if (flags is List) {
            for (final f in flags) {
              if (f is Map) {
                final level = (f['level'] as String?) ?? 'unknown';
                if (level == 'none') continue;
                if (f['acknowledgedAt'] != null) continue;
                entries.add(_FlagRow(
                  uid: uid,
                  level: level,
                  snippet: (f['snippet'] as String?) ?? '',
                  agentId: (f['agentId'] as String?) ?? '',
                  detectedAt: (f['detectedAt'] as String?) ?? '',
                ));
              }
            }
          }
        }
        entries.sort((a, b) => b.detectedAt.compareTo(a.detectedAt));
        if (entries.isEmpty) {
          return _EmptyHint(text: 'No pending flags.');
        }
        return Column(
          children: [for (final e in entries.take(20)) e],
        );
      },
    );
  }
}

class _FlagRow extends StatelessWidget {
  final String uid;
  final String level;
  final String snippet;
  final String agentId;
  final String detectedAt;
  const _FlagRow({
    required this.uid,
    required this.level,
    required this.snippet,
    required this.agentId,
    required this.detectedAt,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = level == 'acute'
        ? theme.colorScheme.errorContainer
        : level == 'moderate'
            ? theme.colorScheme.tertiaryContainer
            : theme.colorScheme.surfaceContainerHighest;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$level · $agentId · $detectedAt',
                style: theme.textTheme.bodySmall),
            const SizedBox(height: 4),
            Text(snippet, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 4),
            Text('uid: $uid', style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _EngagementSummary extends StatelessWidget {
  const _EngagementSummary();

  @override
  Widget build(BuildContext context) {
    final stream = FirebaseFirestore.instance.collection('users').snapshots();
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snap) {
        if (!snap.hasData) return const _Loading();
        final docs = snap.data!.docs;
        var armA = 0, armB = 0, withVariant = 0;
        for (final d in docs) {
          final data = d.data();
          if (data['arm'] == 'A') armA++;
          if (data['arm'] == 'B') armB++;
          if (data['ahJanAhBakVariant'] != null) withVariant++;
        }
        return _StatRow(
          tiles: [
            _StatTile(label: 'Participants', value: docs.length.toString()),
            _StatTile(label: 'Arm A', value: armA.toString()),
            _StatTile(label: 'Arm B', value: armB.toString()),
            _StatTile(label: 'Variant set', value: withVariant.toString()),
          ],
        );
      },
    );
  }
}

class _TranscriptAuditList extends StatelessWidget {
  const _TranscriptAuditList();

  @override
  Widget build(BuildContext context) {
    // Per-user transcript audit needs a separate sampler we'll build
    // out in Phase A polish #2. For now we surface the count of
    // agent_context documents that retained turns, so the researcher
    // can see whether opt-in retention is producing reviewable data.
    final stream = FirebaseFirestore.instance
        .collectionGroup('agent_contexts')
        .snapshots();
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snap) {
        if (!snap.hasData) return const _Loading();
        final docs = snap.data!.docs;
        var withTurns = 0, totalTurns = 0;
        for (final d in docs) {
          final stb = d.data()['shortTermBuffer'];
          if (stb is List && stb.isNotEmpty) {
            withTurns++;
            totalTurns += stb.length;
          }
        }
        return _StatRow(
          tiles: [
            _StatTile(label: 'Agent ctx docs', value: docs.length.toString()),
            _StatTile(label: 'Docs with turns', value: withTurns.toString()),
            _StatTile(label: 'Turns retained', value: totalTurns.toString()),
          ],
        );
      },
    );
  }
}

class _CrossReferralStats extends StatelessWidget {
  const _CrossReferralStats();

  @override
  Widget build(BuildContext context) {
    final stream = FirebaseFirestore.instance
        .collectionGroup('shared_context')
        .snapshots();
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snap) {
        if (!snap.hasData) return const _Loading();
        var proposed = 0;
        var resolved = 0;
        for (final d in snap.data!.docs) {
          final referrals = d.data()['pendingReferrals'];
          if (referrals is List) {
            for (final r in referrals) {
              if (r is Map) {
                proposed++;
                if (r['resolution'] != null) resolved++;
              }
            }
          }
        }
        return _StatRow(
          tiles: [
            _StatTile(label: 'Proposed', value: proposed.toString()),
            _StatTile(label: 'Resolved', value: resolved.toString()),
          ],
        );
      },
    );
  }
}

class _PprAggregates extends StatelessWidget {
  const _PprAggregates();

  @override
  Widget build(BuildContext context) {
    final stream = FirebaseFirestore.instance
        .collectionGroup('ppr_responses')
        .snapshots();
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snap) {
        if (!snap.hasData) return const _Loading();
        final docs = snap.data!.docs;
        final byAgent = <String, List<int>>{};
        for (final d in docs) {
          final agent = (d.data()['agentId'] as String?) ?? 'unknown';
          final items = d.data()['items'];
          if (items is Map) {
            items.forEach((_, v) {
              if (v is int) byAgent.putIfAbsent(agent, () => []).add(v);
            });
          }
        }
        if (byAgent.isEmpty) {
          return const _EmptyHint(text: 'No PPR responses yet.');
        }
        final theme = Theme.of(context);
        return Column(
          children: byAgent.entries.map((e) {
            final mean = e.value.reduce((a, b) => a + b) / e.value.length;
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Expanded(child: Text(e.key)),
                    Text('mean ${mean.toStringAsFixed(2)}'),
                    const SizedBox(width: 12),
                    Text('n ${e.value.length}'),
                  ],
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

class _StatRow extends StatelessWidget {
  final List<_StatTile> tiles;
  const _StatRow({required this.tiles});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (final t in tiles) Expanded(child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: t,
        )),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  const _StatTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Text(value,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
              )),
          const SizedBox(height: 4),
          Text(label,
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator()),
      );
}

class _EmptyHint extends StatelessWidget {
  final String text;
  const _EmptyHint({required this.text});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
    );
  }
}
