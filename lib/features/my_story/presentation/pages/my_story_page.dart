import 'package:flutter/material.dart';

import '../../../../app/app_settings_scope.dart';
import '../../../auth/presentation/auth_service_scope.dart';
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
