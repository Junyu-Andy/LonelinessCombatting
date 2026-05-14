import 'package:flutter/material.dart';

import '../../../../app/app_settings_scope.dart';
import '../../../../core/arm/arm_scope.dart';
import '../../../../core/core_services_scope.dart';
import '../../../../core/llm/llm_gateway.dart';
import '../../../action_loop/data/action_plan.dart';
import '../../../action_loop/presentation/pages/action_loop_arm_a_page.dart';
import '../../../action_loop/presentation/pages/action_loop_arm_b_page.dart';
import '../../../auth/data/auth_service.dart';
import '../../../auth/presentation/auth_service_scope.dart';
import '../../data/suggestion_pool.dart';

/// M6 — Social Activity Suggestions. Both arms share the same screen
/// chrome. Arm A asks the LLM to propose 1–2 suggestions referencing
/// the participant's memory store; Arm B rotates the static pool.
///
/// Spec §M6 trigger: end-of-check-in every 2-3 days, plus a user-tile.
/// Sprint 3 ships the user-tile path. The auto-trigger after Check-in is
/// a one-line route push we'll add in Sprint 4.
class SocialSuggestionsPage extends StatefulWidget {
  const SocialSuggestionsPage({super.key});

  @override
  State<SocialSuggestionsPage> createState() => _SocialSuggestionsPageState();
}

class _SocialSuggestionsPageState extends State<SocialSuggestionsPage> {
  static const _systemPromptZh = '''
你係阿暖，幫一位香港長者諗一兩件可以今日或聽日做嘅小社交活動。
規矩：
- 用粵語/口語繁體中文。
- 出 1 或 2 個建議，每個 1 句，唔超過 35 字。
- 如果提供咗對方提過嘅朋友或屋企人嘅名，盡量自然咁引用。
- 唔好建議要花錢、要長途、要報名嘅活動。
- 唔好用「應該」、「必須」、「你需要」呢類字眼。
- 唔好教訓、唔好提其他 app 功能。
輸出格式：每個建議一行，用 - 開頭。唔好其他文字。
''';

  static const _systemPromptEn = '''
You are a warm companion. Propose one or two small social activities a
Hong Kong older adult could do today or tomorrow.
Rules:
- Reply in plain English.
- Output 1 or 2 suggestions, each one sentence, max 30 words.
- If you know names of friends or family the user has mentioned, weave
  one in naturally.
- Do not suggest expensive, far-away, or commitment-heavy activities.
- Avoid "you should", "you must", "you need to".
- Do not lecture, do not mention other app features.
Output format: one suggestion per line, each starting with "- ". No
other text.
''';

  List<String>? _personalised; // Arm A only
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeLoadArmA());
  }

  Future<void> _maybeLoadArmA() async {
    if (!Arm.isA(context)) return;
    setState(() => _busy = true);
    final core = CoreServicesScope.of(context);
    final profile = AppSettingsScope.read(context).profile;
    final isEn = Localizations.localeOf(context).languageCode == 'en';

    final memorySnips = <String>[];
    if (profile != null) {
      final entries = await core.memory.recentAcross(
        uid: profile.uid,
        moduleIds: const [
          'm2_check_in',
          'm3_reminiscence_w1',
          'm3_reminiscence_w2',
          'm3_reminiscence_w3',
        ],
        perModule: 1,
      );
      memorySnips.addAll(entries.map((e) => '- ${e.summary}'));
    }
    final userInput = memorySnips.isEmpty
        ? (isEn
            ? 'No prior memory yet. Suggest gentle starting actions.'
            : '冇之前嘅記憶。請建議溫和嘅起步行動。')
        : (isEn
            ? 'Prior memory snippets from this user:\n${memorySnips.join('\n')}'
            : '呢位用戶之前提過嘅內容：\n${memorySnips.join('\n')}');

    final response = await core.llm.send(
      moduleId: 'm6_suggestions',
      systemPrompt: isEn ? _systemPromptEn : _systemPromptZh,
      history: const [],
      userInput: userInput,
    );

    if (!mounted) return;
    final lines = response.text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .map((l) => l.startsWith('- ') ? l.substring(2) : l)
        .take(2)
        .toList();
    setState(() {
      _busy = false;
      _personalised = lines.isEmpty ? null : lines;
    });
  }

  void _planFromSuggestion(String suggestion) {
    if (Arm.isA(context)) {
      Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => const ActionLoopArmAPage(),
      ));
    } else {
      Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => const ActionLoopArmBPage(),
      ));
    }
  }

  Future<void> _quickAcceptArmB(SocialSuggestion s) async {
    // Arm B fast path: persist a barebones plan with the suggestion text
    // straight into action_plans so the follow-up loop closes. The user
    // still gets the chance to flesh it out in the planner.
    final profile = AppSettingsScope.read(context).profile;
    final auth = AuthServiceScope.of(context);
    if (profile == null) {
      _planFromSuggestion(s.zh);
      return;
    }
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final repo = ActionPlanRepository(available: auth.available);
    await repo.create(
      profile.uid,
      ActionPlan(
        action: isEn ? s.en : s.zh,
        whenText: '',
        whereText: '',
        whoWith: '',
        fallback: '',
        armCode: 'B',
        createdAt: DateTime.now(),
      ),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(isEn
            ? 'Added to your small steps.'
            : '加咗去「小行動」。'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);
    final pool = const SuggestionPool();
    // Use day-of-year as rotation seed (stable per day per device).
    final seed = DateTime.now().difference(DateTime(DateTime.now().year)).inDays;
    final rotated = pool.rotate(seed: seed);

    return Scaffold(
      appBar: AppBar(
        title: Text(isEn ? 'One small invitation' : '今日嘅小邀請'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            Text(
              isEn
                  ? 'Pick anything that feels right. Skip what doesn\'t.'
                  : '揀一個試下，唔啱就 skip。',
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
            if (Arm.isA(context))
              ..._buildArmA(isEn)
            else
              ..._buildArmB(rotated, isEn),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildArmA(bool isEn) {
    if (_busy) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    final items = _personalised;
    if (items == null || items.isEmpty) {
      // Fall back to the static pool if the model returned nothing.
      return _buildArmB(
        const SuggestionPool().rotate(seed: DateTime.now().day),
        isEn,
      );
    }
    return [
      for (final s in items)
        _SuggestionCard(
          title: s,
          onAccept: () => _planFromSuggestion(s),
          acceptLabel: isEn ? 'Plan it' : '計劃做',
        ),
    ];
  }

  List<Widget> _buildArmB(List<SocialSuggestion> rotated, bool isEn) {
    return [
      for (final s in rotated)
        _SuggestionCard(
          title: isEn ? s.en : s.zh,
          onAccept: () => _quickAcceptArmB(s),
          acceptLabel: isEn ? 'Add to my steps' : '加去我嘅行動',
        ),
    ];
  }
}

class _SuggestionCard extends StatelessWidget {
  final String title;
  final VoidCallback onAccept;
  final String acceptLabel;
  const _SuggestionCard({
    required this.title,
    required this.onAccept,
    required this.acceptLabel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: theme.textTheme.titleMedium?.copyWith(height: 1.4)),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonal(
                  onPressed: onAccept,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    child: Text(acceptLabel,
                        style: const TextStyle(fontSize: 16)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
