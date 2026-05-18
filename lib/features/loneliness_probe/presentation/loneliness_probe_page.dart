/// C.1 — weekly loneliness probe slider page (Sprint 3.3).
///
/// Single 0–10 slider with anchor labels.  Surfaced only when the feature
/// flag is true (Phase B) and the CF cron has queued a pending probe.
library;

import 'package:flutter/material.dart';

import '../../../app/app_settings_scope.dart';
import '../../../core/feature_flags/feature_flags.dart';
import '../../analytics/presentation/analytics_scope.dart';
import '../../auth/presentation/auth_service_scope.dart';
import '../data/loneliness_probe.dart';

class LonelinessProbePage extends StatefulWidget {
  const LonelinessProbePage({super.key});

  @override
  State<LonelinessProbePage> createState() => _LonelinessProbePageState();
}

class _LonelinessProbePageState extends State<LonelinessProbePage> {
  double _value = 5;
  bool _saving = false;

  Future<void> _submit() async {
    final profile = AppSettingsScope.read(context).profile;
    final auth = AuthServiceScope.of(context);
    if (profile == null) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _saving = true);
    final repo = LonelinessProbeRepository(available: auth.available);
    final now = DateTime.now();
    final iso = LonelinessProbeResponse(
      score: _value.round(),
      answeredAt: now,
      // Use the constructor's static helper indirectly.
      isoWeek: LonelinessProbeResponse.fromMap('', {
        'score': 0, 'answeredAt': now.toIso8601String(),
      }).isoWeek,
    );
    await repo.submit(profile.uid, iso);
    if (mounted) {
      await AnalyticsScope.of(context).logEvent('weekly_probe_submitted', {
        'score': _value.round(),
      });
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    // Belt + braces: the route shouldn't even be reachable when the flag
    // is off, but guard here too so a stale deep link can't surface it.
    if (!FeatureFlags.weeklyProbeEnabled) {
      return const Scaffold(body: SizedBox.shrink());
    }
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(isEn ? 'Weekly check' : '每週確認')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Phase B Proposal §7.2 — exact wording locked.
              Text(
                isEn
                    ? "Over the past week, how often did you feel lonely?"
                    : '過去一個星期，你幾經常覺得孤獨？',
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 28),
              Slider(
                value: _value,
                onChanged: (v) => setState(() => _value = v),
                min: 0,
                max: 10,
                divisions: 10,
                label: _value.round().toString(),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(isEn ? 'Not at all' : '完全冇',
                      style: theme.textTheme.bodySmall),
                  Text(isEn ? 'Very much' : '非常',
                      style: theme.textTheme.bodySmall),
                ],
              ),
              const Spacer(),
              FilledButton(
                onPressed: _saving ? null : _submit,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(isEn ? 'Submit' : '提交',
                      style: const TextStyle(fontSize: 18)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
