import 'package:flutter/material.dart';

import '../../../../app/app_settings_scope.dart';
import '../../../auth/presentation/auth_service_scope.dart';
import '../../../reflective_dialogue/presentation/pages/reflective_dialogue_page.dart';
import '../../data/my_story_progress.dart';
import '../widgets/current_session_entry.dart';
import '../widgets/current_week_hero.dart';
import '../widgets/session_history_list.dart';
import '../widgets/story_thread_timeline.dart';

/// My Story tab — the home of M3 (reminiscence / life review). Loads
/// progress on first build; while loading shows an empty-state arc so
/// the layout doesn't jump.
class MyStoryPage extends StatefulWidget {
  const MyStoryPage({super.key});

  @override
  State<MyStoryPage> createState() => _MyStoryPageState();
}

class _MyStoryPageState extends State<MyStoryPage> {
  MyStoryProgress _progress = MyStoryProgress.empty();
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
    final auth = AuthServiceScope.of(context);
    if (profile == null) return;
    final reader = MyStoryProgressReader(available: auth.available);
    final progress = await reader.read(
      uid: profile.uid,
      referenceDate: DateTime.now(),
      userCreatedAt: profile.createdAt,
    );
    if (!mounted) return;
    setState(() => _progress = progress);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          CurrentWeekHero(progress: _progress),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CurrentSessionEntry(week: _progress.currentWeek),
                const SizedBox(height: 16),
                _ReflectiveChatEntry(),
                const SizedBox(height: 24),
                StoryThreadTimeline(progress: _progress),
                const SizedBox(height: 24),
                SessionHistoryList(progress: _progress),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Open-ended reflective chat entry point. Lives in My Story (Ah Jan /
/// Ah Bak's tab) rather than the weekly hero so it doesn't visually
/// compete with the curriculum.
class _ReflectiveChatEntry extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.secondaryContainer,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const ReflectiveDialoguePage(),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.chat_bubble_outline,
                  size: 28,
                  color: theme.colorScheme.onSecondaryContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isEn ? 'Reflective chat' : '反思傾偈',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSecondaryContainer,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isEn
                          ? 'Open-ended chat — not part of the weekly curriculum.'
                          : '隨意傾偈，唔屬於今週嘅 session。',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSecondaryContainer,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  color: theme.colorScheme.onSecondaryContainer),
            ],
          ),
        ),
      ),
    );
  }
}
