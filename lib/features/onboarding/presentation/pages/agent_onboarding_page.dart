/// Post-consent agent onboarding (Developer Requirements §M1, §3, §4.5).
///
/// After the participant accepts the functional-data consent, this flow:
///   1. Introduces the three agents at a high level.
///   2. Walks through each agent one at a time (Siu Yan → Ah Jan/Ah Bak
///      → Tung Tung), letting them read the persona and AI-identity
///      statement.
///   3. Captures the Ah Jan / Ah Bak gender variant (required step —
///      gates progression on this screen).
///   4. Captures Tung Tung's interest profile via a multi-select.
///   5. Surfaces per-agent transcript retention toggles (Dev Req §4.5).
///      Phase A copy defaults each toggle to ON because the pilot needs
///      transcript data, but participants may turn any of them off.
///
/// At completion the page writes the profile fields and pops; the
/// [OnboardingGate] (mounted under [ConsentGate]) reroutes to the main
/// shell on the next AppSettings notification.
library;

import 'dart:math';

import 'package:flutter/material.dart';

import '../../../../app/app_settings_scope.dart';
import '../../../../core/agents/agent_avatar.dart';
import '../../../../core/agents/agent_registry.dart';
import '../../../auth/data/auth_service.dart';
import '../../../auth/data/user_profile.dart';
import '../../../auth/presentation/auth_service_scope.dart';

class AgentOnboardingPage extends StatefulWidget {
  const AgentOnboardingPage({super.key});

  @override
  State<AgentOnboardingPage> createState() => _AgentOnboardingPageState();
}

class _AgentOnboardingPageState extends State<AgentOnboardingPage> {
  final _pageController = PageController();
  int _pageIndex = 0;

  AgentGenderVariant? _ahJanVariant;
  final Set<String> _selectedInterests = {};
  late final List<_InterestSeed> _shuffledSeeds;

  /// Phase A defaults transcript retention to ON for every agent.
  /// The matching informed-consent statement is collected on paper
  /// rather than in the app per the May-2026 review, so we no longer
  /// surface the per-agent toggles here.
  static const Map<String, bool> _transcriptRetentionByAgent = {
    AgentRegistry.siuYanId: true,
    AgentRegistry.ahJanAhBakId: true,
    AgentRegistry.tungTungId: true,
  };

  bool _busy = false;
  String? _error;

  /// Research Review v2 Item 4: 24-candidate interest pool across 6 categories.
  /// Cultural advisor review required before Phase A recruitment opens.
  /// ⚠️ Items marked with risk notes: mobility assumptions (hiking, swimming),
  /// retirement-loss assumption (past work), social network assumption (church,
  /// volunteering). All retained pending advisor sign-off.
  ///
  /// Escape hatch "__skip__" must be handled specially: selecting it clears all
  /// others; selecting any other item clears it.
  static const List<_InterestSeed> _interestSeeds = [
    // 飲食類
    _InterestSeed(id: 'yum_cha',      zh: '飲茶／一盅兩件', en: 'Yum cha / dim sum'),
    _InterestSeed(id: 'cooking',      zh: '煮食',           en: 'Cooking'),
    _InterestSeed(id: 'wet_market',   zh: '逛街市',         en: 'Wet market'),
    _InterestSeed(id: 'buffet',       zh: '食自助餐',       en: 'Buffet dining'),
    // 休閒類
    _InterestSeed(id: 'tv_drama',     zh: '睇電視劇',       en: 'TV drama'),
    _InterestSeed(id: 'radio',        zh: '聽收音機',       en: 'Radio'),
    _InterestSeed(id: 'reading',      zh: '看書／睇雜誌',   en: 'Books / magazines'),
    _InterestSeed(id: 'mahjong',      zh: '打牌／打麻雀',   en: 'Cards / mahjong'),
    _InterestSeed(id: 'gardening',    zh: '種花種菜',       en: 'Gardening'),
    _InterestSeed(id: 'chatting',     zh: '跟人傾偈',       en: 'Chatting with people'),
    // 運動類
    _InterestSeed(id: 'hiking',       zh: '行山',           en: 'Hiking'), // ⚠️ mobility
    _InterestSeed(id: 'park_walk',    zh: '公園散步',       en: 'Park walks'),
    _InterestSeed(id: 'tai_chi',      zh: '太極拳',         en: 'Tai chi'),
    _InterestSeed(id: 'swimming',     zh: '游水',           en: 'Swimming'), // ⚠️ mobility
    // 文化類
    _InterestSeed(id: 'cantonese_opera', zh: '粵劇／戲曲',  en: 'Cantonese opera'),
    _InterestSeed(id: 'museums',      zh: '睇展覽／博物館', en: 'Museums & galleries'),
    // 社交類
    _InterestSeed(id: 'elderly_centre', zh: '老人中心活動', en: 'Elderly centre activities'),
    _InterestSeed(id: 'religious',    zh: '去教會／廟宇',   en: 'Church / temple'), // ⚠️ social network
    _InterestSeed(id: 'visit_friends',zh: '探望朋友',       en: 'Visiting friends'),
    _InterestSeed(id: 'volunteering', zh: '義工服務',       en: 'Volunteering'), // ⚠️ social network
    // 宗教／精神類
    _InterestSeed(id: 'meditation',   zh: '靜坐／冥想',     en: 'Meditation'),
    _InterestSeed(id: 'prayer',       zh: '祈禱／膜拜',     en: 'Prayer / worship'),
    // 實用類
    _InterestSeed(id: 'news',         zh: '新聞時事',       en: 'News & current affairs'),
    // Escape hatch — selecting this clears all other selections.
    _InterestSeed(id: '__skip__',     zh: '我未諗到 / 跳過', en: 'Not sure / skip'),
  ];

  @override
  void initState() {
    super.initState();
    // Shuffle per session so each participant sees a different chip order.
    // Escape hatch always stays last.
    final rng = Random(DateTime.now().millisecondsSinceEpoch);
    final nonSkip = List<_InterestSeed>.from(
      _interestSeeds.where((s) => s.id != '__skip__'),
    )..shuffle(rng);
    _shuffledSeeds = [...nonSkip, _interestSeeds.last];
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_pageIndex >= _pageCount - 1) return;
    _pageController.nextPage(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  void _prevPage() {
    if (_pageIndex == 0) return;
    _pageController.previousPage(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  int get _pageCount => 4;

  Future<void> _finish() async {
    final auth = AuthServiceScope.of(context);
    final settings = AppSettingsScope.read(context);
    final profile = settings.profile;
    if (profile == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final updated = profile.copyWith(
      ahJanAhBakVariant:
          _ahJanVariant ?? AgentGenderVariant.feminine, // gated above
      // Filter escape hatch before saving — "__skip__" is UI-only.
      interests: _selectedInterests.where((id) => id != '__skip__').toList(),
      consent: profile.consent.copyWith(
        transcriptRetentionByAgent: _transcriptRetentionByAgent,
      ),
    );
    try {
      await auth.updateProfile(updated);
    } on AuthUnavailableException {
      // Guest mode — keep state in memory.
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.toString();
      });
      return;
    }
    if (!mounted) return;
    settings.profile = updated;
  }

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);

    final lastPage = _pageIndex == _pageCount - 1;
    final canAdvance = _canAdvanceFrom(_pageIndex);

    return Scaffold(
      appBar: AppBar(
        title: Text(isEn ? 'Meet the three of us' : '介紹三個夥伴'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
              child: _StepDots(
                count: _pageCount,
                current: _pageIndex,
                color: theme.colorScheme.primary,
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (i) => setState(() => _pageIndex = i),
                children: [
                  _IntroWelcome(isEn: isEn),
                  _AgentIntroSlide(
                    isEn: isEn,
                    agent: AgentRegistry.byId(AgentRegistry.siuYanId),
                  ),
                  _AhJanAhBakSlide(
                    isEn: isEn,
                    selected: _ahJanVariant,
                    onSelect: (v) => setState(() => _ahJanVariant = v),
                  ),
                  _TungTungSlide(
                    isEn: isEn,
                    seeds: _shuffledSeeds,
                    selected: _selectedInterests,
                    onToggle: (id) => setState(() {
                      if (id == '__skip__') {
                        // Escape hatch: clear all others, toggle skip.
                        if (_selectedInterests.contains('__skip__')) {
                          _selectedInterests.clear();
                        } else {
                          _selectedInterests
                            ..clear()
                            ..add('__skip__');
                        }
                      } else {
                        // Any real interest: deselect escape hatch if active.
                        _selectedInterests.remove('__skip__');
                        if (_selectedInterests.contains(id)) {
                          _selectedInterests.remove(id);
                        } else {
                          _selectedInterests.add(id);
                        }
                      }
                    }),
                    errorMessage: _error,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 18),
              child: Row(
                children: [
                  TextButton(
                    onPressed: _pageIndex == 0 || _busy ? null : _prevPage,
                    child: Text(
                      isEn ? 'Back' : '上一步',
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: !canAdvance || _busy
                        ? null
                        : (lastPage ? _finish : _nextPage),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      child: Text(
                        lastPage
                            ? (isEn ? 'Done' : '完成')
                            : (isEn ? 'Next' : '下一步'),
                        style: const TextStyle(fontSize: 18),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _canAdvanceFrom(int index) {
    // Variant selection is the only required field on its page.
    if (index == 2) return _ahJanVariant != null;
    return true;
  }
}

class _StepDots extends StatelessWidget {
  final int count;
  final int current;
  final Color color;

  const _StepDots({
    required this.count,
    required this.current,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final active = i == current;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: active ? 22 : 10,
          height: 10,
          decoration: BoxDecoration(
            color: active ? color : color.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(5),
          ),
        );
      }),
    );
  }
}

class _IntroWelcome extends StatelessWidget {
  final bool isEn;
  const _IntroWelcome({required this.isEn});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isEn
                ? 'Three AI companions, each with a different role'
                : '三個 AI 夥伴，各有唔同角色',
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: 14),
          Text(
            isEn
                ? 'These are AI robots, not people. They will not replace '
                    'your relationships with real friends and family. Each '
                    'one is designed for a specific kind of conversation, '
                    'so you choose who to talk to based on what you want '
                    'to share today.'
                : '佢哋係 AI 機械人，唔係真人，亦都唔會代替你身邊嘅家人朋友。'
                    '佢哋每一個都係專門做一件事，所以你想傾乜，就揀對應嘅夥伴。',
            style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
          ),
          const SizedBox(height: 24),
          for (final agent in AgentRegistry.all) _AgentSummaryRow(agent: agent),
        ],
      ),
    );
  }
}

class _AgentSummaryRow extends StatelessWidget {
  final AgentDefinition agent;
  const _AgentSummaryRow({required this.agent});

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);
    final variant = agent.resolveVariant(null);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          AgentAvatar(agent: agent, size: 56),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isEn ? variant.displayNameEn : variant.displayNameZh,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: agent.accentColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  isEn ? agent.tileSubtitleEn : agent.tileSubtitleZh,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AgentIntroSlide extends StatelessWidget {
  final bool isEn;
  final AgentDefinition agent;
  const _AgentIntroSlide({required this.isEn, required this.agent});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final variant = agent.resolveVariant(null);
    final intro = AgentRegistry.introTextFor(agent.introTextKey);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          AgentAvatar(agent: agent, size: 120),
          const SizedBox(height: 18),
          Text(
            isEn ? variant.displayNameEn : variant.displayNameZh,
            style: theme.textTheme.displaySmall?.copyWith(
              color: agent.accentColor,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            isEn ? agent.tileSubtitleEn : agent.tileSubtitleZh,
            style: theme.textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          if (intro != null)
            Card(
              color: agent.accentColor.withValues(alpha: 0.12),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Text(
                  isEn ? intro.en : intro.zh,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    height: 1.5,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AhJanAhBakSlide extends StatelessWidget {
  final bool isEn;
  final AgentGenderVariant? selected;
  final ValueChanged<AgentGenderVariant> onSelect;

  const _AhJanAhBakSlide({
    required this.isEn,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final agent = AgentRegistry.byId(AgentRegistry.ahJanAhBakId);
    final intro = AgentRegistry.introTextFor(agent.introTextKey);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Column(
              children: [
                Wrap(
                  spacing: 24,
                  children: [
                    AgentAvatar(
                      agent: agent,
                      selectedVariant: AgentGenderVariant.feminine,
                      size: 96,
                    ),
                    AgentAvatar(
                      agent: agent,
                      selectedVariant: AgentGenderVariant.masculine,
                      size: 96,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  isEn ? 'Ah Jan / Ah Bak' : '阿珍 ／ 阿伯',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: agent.accentColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  isEn ? agent.tileSubtitleEn : agent.tileSubtitleZh,
                  style: theme.textTheme.bodyLarge,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          if (intro != null)
            Card(
              color: agent.accentColor.withValues(alpha: 0.12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  isEn ? intro.en : intro.zh,
                  style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
                ),
              ),
            ),
          const SizedBox(height: 22),
          Text(
            isEn
                ? 'Choose who you would like to hear from'
                : '揀邊個陪你做人生回顧',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 10),
          _VariantChoice(
            label: isEn ? 'Ah Jan (peer · she)' : '阿珍（同輩女性）',
            value: AgentGenderVariant.feminine,
            selected: selected,
            onSelect: onSelect,
            accent: agent.accentColor,
          ),
          const SizedBox(height: 8),
          _VariantChoice(
            label: isEn ? 'Ah Bak (peer · he)' : '阿伯（同輩男性）',
            value: AgentGenderVariant.masculine,
            selected: selected,
            onSelect: onSelect,
            accent: agent.accentColor,
          ),
          const SizedBox(height: 10),
          Text(
            isEn
                ? 'You can change this any time in Settings.'
                : '之後可以喺「設定」入面更改。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _VariantChoice extends StatelessWidget {
  final String label;
  final AgentGenderVariant value;
  final AgentGenderVariant? selected;
  final ValueChanged<AgentGenderVariant> onSelect;
  final Color accent;

  const _VariantChoice({
    required this.label,
    required this.value,
    required this.selected,
    required this.onSelect,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isSelected = selected == value;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => onSelect(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected
              ? accent.withValues(alpha: 0.15)
              : theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? accent : theme.colorScheme.outlineVariant,
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Icon(
              isSelected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color:
                  isSelected ? accent : theme.colorScheme.onSurfaceVariant,
              size: 26,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label, style: theme.textTheme.titleMedium),
            ),
          ],
        ),
      ),
    );
  }
}

class _TungTungSlide extends StatelessWidget {
  final bool isEn;
  final List<_InterestSeed> seeds;
  final Set<String> selected;
  final ValueChanged<String> onToggle;
  final String? errorMessage;

  const _TungTungSlide({
    required this.isEn,
    required this.seeds,
    required this.selected,
    required this.onToggle,
    this.errorMessage,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final agent = AgentRegistry.byId(AgentRegistry.tungTungId);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: AgentAvatar(agent: agent, size: 96)),
          const SizedBox(height: 12),
          Center(
            child: Text(
              isEn ? 'Tung Tung' : '通通',
              style: theme.textTheme.headlineSmall?.copyWith(
                color: agent.accentColor,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Center(
            child: Text(
              isEn ? agent.tileSubtitleEn : agent.tileSubtitleZh,
              style: theme.textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 22),
          Text(
            isEn ? 'What do you like?' : '你鍾意啲咩？',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            isEn
                ? 'Pick any that apply — Tung Tung will use these to start '
                    'conversations. You can change this any time.'
                : '揀啱嘅嘢 —— 通通會用嚟搵話題。之後可以隨時改。',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final seed in seeds)
                FilterChip(
                  label: Text(
                    isEn ? seed.en : seed.zh,
                    // Explicit label colour fixes the M3 default that
                    // rendered as low-contrast white-on-grey for our
                    // older-adult target audience.
                    style: TextStyle(
                      fontSize: 15,
                      // Escape hatch: italic to visually separate from topic chips.
                      fontStyle: seed.id == '__skip__'
                          ? FontStyle.italic
                          : FontStyle.normal,
                      fontWeight: selected.contains(seed.id)
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: seed.id == '__skip__'
                          ? theme.colorScheme.onSurfaceVariant
                          : selected.contains(seed.id)
                              ? agent.accentColor.withValues(alpha: 1.0)
                              : theme.colorScheme.onSurface,
                    ),
                  ),
                  selected: selected.contains(seed.id),
                  onSelected: (_) => onToggle(seed.id),
                  // Unselected: opaque surface so text reads cleanly;
                  // border carries the agent accent at low alpha.
                  backgroundColor: theme.colorScheme.surface,
                  selectedColor: seed.id == '__skip__'
                      ? theme.colorScheme.surfaceContainerHighest
                      : agent.accentColor.withValues(alpha: 0.18),
                  checkmarkColor: seed.id == '__skip__'
                      ? theme.colorScheme.onSurfaceVariant
                      : agent.accentColor,
                  side: BorderSide(
                    color: seed.id == '__skip__'
                        ? theme.colorScheme.outlineVariant
                        : selected.contains(seed.id)
                            ? agent.accentColor
                            : theme.colorScheme.outline,
                    width: selected.contains(seed.id) ? 2 : 1,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            isEn
                ? 'Tap "Done" to finish setup and meet your companions.'
                : '撳「完成」就可以開始同夥伴傾偈。',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface,
            ),
          ),
          if (errorMessage != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                errorMessage!,
                style: TextStyle(color: theme.colorScheme.onErrorContainer),
              ),
            ),
          ],
        ],
      ),
    );
  }
}


class _InterestSeed {
  final String id;
  final String zh;
  final String en;
  const _InterestSeed({required this.id, required this.zh, required this.en});
}
