/// M-3 — one-question daily mood prompt (Phase A baseline 2026-09).
///
/// Shown once on the first home-page build of each local day when no mood
/// has been recorded for today; skippable; never pushed.  Writes the normal
/// `daily_mood` entry via [MoodRecorder] (so the home pad, Siu Yan opener
/// and `[Recent mood snippet]` all see it) and logs a `mood_checkin` event
/// with `skipped: true|false`.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../app/app_settings_scope.dart';
import '../../../../core/agent_context/shared_context_service.dart';
import '../../../../core/arm/arm_scope.dart';
import '../../../../core/core_services_scope.dart';
import '../../../../core/session/chat_session_recorder.dart';
import '../../../../core/time/app_clock.dart';
import '../../../analytics/presentation/analytics_scope.dart';
import '../../../context/presentation/pages/check_in_shared.dart';
import '../../data/mood_recorder.dart';

class DailyMoodPrompt {
  DailyMoodPrompt._();

  /// Local date (YYYY-MM-DD) the prompt last ran in this process, so a
  /// rebuild or tab switch never re-asks.
  static String? _promptedDateIso;

  @visibleForTesting
  static void resetForTest() => _promptedDateIso = null;

  /// Call from the home page once per build; safe to call repeatedly.
  static Future<void> maybeShow(BuildContext context) async {
    final today = MoodRecorder.dateIsoFor(AppClock.now());
    if (_promptedDateIso == today) return;
    final profile = AppSettingsScope.read(context).profile;
    if (profile == null) return;
    _promptedDateIso = today;
    final recorder = MoodRecorder();
    final existing = await recorder.latestForDate(uid: profile.uid, dateIso: today);
    if (existing != null || !context.mounted) return;
    final analytics = AnalyticsScope.of(context);
    final sharedContext = CoreServicesScope.of(context).sharedContext;
    final isArmA = Arm.isA(context);
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final picked = await showModalBottomSheet<int?>(
      context: context,
      isDismissible: true,
      showDragHandle: true,
      builder: (ctx) => _MoodSheet(isEn: isEn),
    );
    if (picked == null) {
      unawaited(analytics.logEvent(PhaseAEvents.moodCheckin, {
        'skipped': true,
        'source': 'daily_prompt',
      }));
      return;
    }
    unawaited(() async {
      try {
        await recorder.record(
          uid: profile.uid,
          mood: picked,
          arm: isArmA ? 'A' : 'B',
          sourceSurface: 'daily_prompt',
        );
      } catch (_) {}
    }());
    // M-3 — Siu Yan's `[Recent mood snippet]` is read from shared context,
    // so the daily prompt must feed it too (previously only the check-in
    // page did).
    unawaited(() async {
      try {
        await sharedContext.updateRecentMood(
          uid: profile.uid,
          mood: SharedMoodSummary(
            summary: '最近一次心情評分：$picked/5。',
            asOf: DateTime.now(),
          ),
        );
      } catch (_) {}
    }());
    unawaited(analytics.logEvent(PhaseAEvents.moodCheckin, {
      'skipped': false,
      'mood': picked,
      'source': 'daily_prompt',
    }));
    unawaited(analytics.logDailyMoodSubmitted(mood: picked));
  }
}

class _MoodSheet extends StatefulWidget {
  final bool isEn;
  const _MoodSheet({required this.isEn});

  @override
  State<_MoodSheet> createState() => _MoodSheetState();
}

class _MoodSheetState extends State<_MoodSheet> {
  MoodFace? _face;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEn = widget.isEn;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              isEn ? 'How are you feeling today?' : '你今日心情點？',
              style: theme.textTheme.titleLarge?.copyWith(fontSize: 22),
            ),
            const SizedBox(height: 18),
            MoodFacePicker(
              value: _face,
              onChanged: (v) => setState(() => _face = v),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _face == null
                  ? null
                  : () => Navigator.of(context).pop(_face!.numericScore),
              style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 56)),
              child: Text(isEn ? 'Done' : '完成', style: const TextStyle(fontSize: 18)),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: Text(isEn ? 'Skip for today' : '今日跳過',
                  style: const TextStyle(fontSize: 16)),
            ),
          ],
        ),
      ),
    );
  }
}
