import 'package:flutter/material.dart';

import '../../../../app/app_settings_scope.dart';
import '../../../../core/arm/arm_scope.dart';
import '../../../../core/core_services_scope.dart';
import '../../../../core/llm/llm_gateway.dart';
import '../../../auth/data/auth_service.dart';
import '../../../auth/presentation/auth_service_scope.dart';
import '../../data/progress_data.dart';

/// M9 — Progress Tracking. Identical chart chrome across arms. Arm A
/// shows an LLM-generated weekly narrative; Arm B shows a static
/// template summary.
class ProgressPage extends StatefulWidget {
  const ProgressPage({super.key});

  @override
  State<ProgressPage> createState() => _ProgressPageState();
}

class _ProgressPageState extends State<ProgressPage> {
  static const _systemPromptZh = '''
你係阿暖。睇住呢位香港長者過去 7 日嘅活動數字，寫一段 2-3 句嘅週小結。
要求：
- 用粵語/口語繁體中文。
- 提到 1 個具體數字（例如「呢個禮拜你做咗 3 次 check-in」）。
- 如果有完成嘅計劃，認可佢。如果冇，唔好責備、亦唔好催促。
- 唔好教訓，唔好提其他 app 功能。
輸出：只係段話本身。
''';

  static const _systemPromptEn = '''
You write a 2-3 sentence weekly summary for a Hong Kong older adult,
looking at the past 7 days of their activity counts.
Rules:
- Plain English.
- Mention one concrete number (e.g. "you checked in 3 times").
- Acknowledge completed plans if any. If none, don't reproach or push.
- No lectures, no mentioning of other app features.
Output: only the paragraph itself.
''';

  WeeklyProgress? _data;
  String? _summary;
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final profile = AppSettingsScope.read(context).profile;
    final auth = AuthServiceScope.of(context);
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    if (profile == null) {
      setState(() {
        _busy = false;
        _data = WeeklyProgress.empty;
        _summary = isEn
            ? 'Sign in to see your weekly summary.'
            : '登入之後可以睇到每週小結。';
      });
      return;
    }
    final repo = ProgressRepository(available: auth.available);
    WeeklyProgress data;
    try {
      data = await repo.load(profile.uid);
    } catch (_) {
      // Firestore quota / network blip — show empties instead of
      // crashing the whole page.
      data = WeeklyProgress.empty;
    }
    if (!mounted) return;
    setState(() {
      _data = data;
      _busy = false;
    });
    if (Arm.isA(context)) {
      _generateLlmSummary(data, isEn);
    } else {
      setState(() => _summary = _staticSummary(data, isEn));
    }
  }

  Future<void> _generateLlmSummary(WeeklyProgress d, bool isEn) async {
    final core = CoreServicesScope.of(context);
    final response = await core.llm.send(
      moduleId: 'm9_progress_summary',
      systemPrompt: isEn ? _systemPromptEn : _systemPromptZh,
      history: const [],
      userInput: [
        'check-ins: ${d.moodScores.length}',
        'days with contact: ${d.contactDays}',
        'plans authored: ${d.plansAuthored}',
        'plans followed up: ${d.plansFollowedUp}',
        'reminiscence sessions: ${d.reminiscenceSessions}',
        if (d.moodScores.isNotEmpty)
          'avg mood (1-5): ${(d.moodScores.reduce((a, b) => a + b) / d.moodScores.length).toStringAsFixed(1)}',
      ].join('\n'),
    );
    if (!mounted) return;
    setState(() {
      _summary = response.text.isNotEmpty
          ? response.text
          : _staticSummary(d, isEn);
    });
  }

  String _staticSummary(WeeklyProgress d, bool isEn) {
    if (isEn) {
      final lines = <String>[];
      lines.add('Past 7 days at a glance:');
      lines.add('• Check-ins: ${d.moodScores.length}');
      lines.add('• Plans you made: ${d.plansAuthored}');
      lines.add('• Plans you followed up on: ${d.plansFollowedUp}');
      lines.add('• Reminiscence sessions: ${d.reminiscenceSessions}');
      return lines.join('\n');
    }
    final lines = <String>[];
    lines.add('呢個禮拜：');
    lines.add('• Check-in：${d.moodScores.length} 次');
    lines.add('• 計劃咗：${d.plansAuthored} 個');
    lines.add('• 跟進咗：${d.plansFollowedUp} 個');
    lines.add('• 人生點滴：${d.reminiscenceSessions} 節');
    return lines.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(isEn ? 'Your week' : '你嘅一個禮拜')),
      body: SafeArea(
        child: _busy
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: _summary == null
                          ? const SizedBox(
                              height: 36,
                              child: Center(
                                  child: CircularProgressIndicator()),
                            )
                          : Text(
                              _summary!,
                              style: theme.textTheme.bodyLarge
                                  ?.copyWith(height: 1.5),
                            ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(isEn ? 'Mood (1–5)' : '心情（1-5）',
                      style: theme.textTheme.titleLarge),
                  const SizedBox(height: 8),
                  _BarChart(values: _data?.moodScores ?? const []),
                  const SizedBox(height: 20),
                  Text(isEn ? 'Counts' : '數量',
                      style: theme.textTheme.titleLarge),
                  const SizedBox(height: 8),
                  _CountTile(
                    label: isEn ? 'Check-ins' : 'Check-in',
                    value: _data?.moodScores.length ?? 0,
                  ),
                  _CountTile(
                    label: isEn ? 'Plans made' : '計劃咗',
                    value: _data?.plansAuthored ?? 0,
                  ),
                  _CountTile(
                    label:
                        isEn ? 'Plans followed up' : '跟進咗',
                    value: _data?.plansFollowedUp ?? 0,
                  ),
                  _CountTile(
                    label: isEn
                        ? 'Reminiscence sessions'
                        : '人生點滴',
                    value: _data?.reminiscenceSessions ?? 0,
                  ),
                ],
              ),
      ),
    );
  }
}

/// Minimal, accessible bar chart built with Containers so the elder-
/// friendly theme's font scaling applies and we don't pull in a chart
/// dependency for a 7-bar visual.
class _BarChart extends StatelessWidget {
  final List<int> values;
  const _BarChart({required this.values});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (values.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(
          Localizations.localeOf(context).languageCode == 'en'
              ? 'No check-ins yet this week.'
              : '今個禮拜暫時冇 check-in。',
          style: theme.textTheme.bodyLarge,
        ),
      );
    }
    return Container(
      height: 140,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: values.map((v) {
          final h = (v.clamp(1, 5)) / 5 * 100;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Container(
                    height: h,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(6)),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text('$v',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      )),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _CountTile extends StatelessWidget {
  final String label;
  final int value;
  const _CountTile({required this.label, required this.value});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
          title: Text(label, style: theme.textTheme.titleMedium),
          trailing: Text(
            '$value',
            style: theme.textTheme.headlineSmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}
