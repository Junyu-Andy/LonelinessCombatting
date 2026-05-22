import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../../app/app_settings_scope.dart';
import '../../../my_story/data/my_story_progress.dart';
import '../../data/mood_recorder.dart';

/// Home Layout Spec §4 — one-line factual recap, two-arm-identical,
/// template-only (never LLM).  Example: "今個星期 · 傾咗 4 次 · 記錄 5
/// 次心情 · 阿珍講到第 2 章".
///
/// All counts are pure read-only aggregations over existing
/// collections; nothing is written here.  Hidden silently while
/// loading so it never causes a layout pop.
class FactsRecapRow extends StatefulWidget {
  const FactsRecapRow({super.key});

  @override
  State<FactsRecapRow> createState() => _FactsRecapRowState();
}

class _FactsRecapRowState extends State<FactsRecapRow> {
  _Recap? _recap;
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) {
      _loaded = true;
      _load();
    }
  }

  Future<void> _load() async {
    final profile = AppSettingsScope.read(context).profile;
    if (profile == null) return;
    final now = DateTime.now();
    final weekStart = now.subtract(const Duration(days: 7));

    int conversations = 0;
    int moodDays = 0;
    int? reminWeek;

    try {
      final db = FirebaseFirestore.instance;
      final eventsSnap = await db
          .collection('users')
          .doc(profile.uid)
          .collection('events')
          .where('name', whereIn: const [
        'm2_check_in_submitted',
        'm3_session_end',
        'm5_reflective_session_end',
        'm8_article_opened',
      ]).get();
      conversations = eventsSnap.docs.where((d) {
        final raw = d.data()['timestamp'];
        final t = raw is Timestamp
            ? raw.toDate()
            : (raw is String ? DateTime.tryParse(raw) : null);
        return t != null && t.isAfter(weekStart);
      }).length;
    } catch (_) {}

    try {
      moodDays = await MoodRecorder().distinctDaysInRange(
        uid: profile.uid,
        from: weekStart,
        until: now.add(const Duration(days: 1)),
      );
    } catch (_) {}

    try {
      final reader = MyStoryProgressReader(available: true);
      final progress = await reader.read(
        uid: profile.uid,
        referenceDate: now,
        userCreatedAt: profile.createdAt,
      );
      reminWeek = progress.currentWeekIndex;
    } catch (_) {}

    if (!mounted) return;
    setState(() => _recap = _Recap(
          conversations: conversations,
          moodDays: moodDays,
          reminWeek: reminWeek,
        ));
  }

  @override
  Widget build(BuildContext context) {
    final r = _recap;
    if (r == null) return const SizedBox(height: 28);
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final parts = <Widget>[];

    parts.add(_label(isEn ? 'This week' : '今個星期'));
    parts.add(_chip(
      icon: Icons.chat_bubble_outline,
      text: isEn
          ? '${r.conversations} chat${r.conversations == 1 ? '' : 's'}'
          : '傾咗 ${r.conversations} 次',
    ));
    parts.add(_dot());
    parts.add(_chip(
      icon: Icons.sentiment_satisfied_outlined,
      text: isEn
          ? '${r.moodDays} mood${r.moodDays == 1 ? '' : 's'}'
          : '記錄 ${r.moodDays} 次心情',
    ));
    if (r.reminWeek != null) {
      parts.add(_dot());
      parts.add(_chip(
        text: isEn
            ? 'Ah Jan · Ch.${r.reminWeek}'
            : '阿珍講到第 ${r.reminWeek} 章',
      ));
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(
            top: BorderSide(color: Color(0xFFECE5DB), width: 1),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: parts,
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Text(
        text,
        style: const TextStyle(color: Color(0xFFB0A496), fontSize: 12),
      );

  Widget _dot() => const Text(
        '·',
        style: TextStyle(color: Color(0xFFD8CFC3), fontSize: 12),
      );

  Widget _chip({IconData? icon, required String text}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 14, color: const Color(0xFF8A7D72)),
          const SizedBox(width: 4),
        ],
        Text(
          text,
          style: const TextStyle(color: Color(0xFF8A7D72), fontSize: 12),
        ),
      ],
    );
  }
}

class _Recap {
  final int conversations;
  final int moodDays;
  final int? reminWeek;
  const _Recap({
    required this.conversations,
    required this.moodDays,
    required this.reminWeek,
  });
}
