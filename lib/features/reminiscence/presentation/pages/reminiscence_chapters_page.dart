/// 1020d 6 (8) — 「我嘅人生小篇章」: the finished chapters by week, entered
/// from the reminiscence landing page (switch `reminiscenceV2Enabled`).
/// Each one opens to the full text and can be 「改一改」 again (the edit
/// ratio is always against the original).  No sharing.  Both arms the
/// same; nothing here calls the LLM.
library;

import 'package:flutter/material.dart';

import '../../../../app/app_settings_scope.dart';
import '../../../../core/agents/agent_registry.dart';
import '../../../../core/agents/companion_app_bar.dart';
import '../../../../shared/widgets/keyboard_compact.dart';
import '../../../auth/presentation/auth_service_scope.dart';
import '../../data/reminiscence_v2_copy.dart';
import '../../data/reminiscence_v2_models.dart';
import '../../data/reminiscence_v2_store.dart';
import '../widgets/reminiscence_chapter_card.dart';
import 'reminiscence_v2_page.dart';

class ReminiscenceChaptersPage extends StatefulWidget {
  const ReminiscenceChaptersPage({super.key});

  @override
  State<ReminiscenceChaptersPage> createState() =>
      _ReminiscenceChaptersPageState();
}

class _ReminiscenceChaptersPageState extends State<ReminiscenceChaptersPage> {
  List<ReminiscenceChapterDoc>? _chapters;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _load();
  }

  Future<void> _load() async {
    final uid = AppSettingsScope.read(context).profile?.uid;
    final store = ReminiscenceV2Stores.chapters(
        available: AuthServiceScope.of(context).available);
    final all = uid == null ? const <ReminiscenceChapterDoc>[] : await store.list(uid);
    if (!mounted) return;
    setState(() => _chapters = [for (final c in all) if (c.isReady) c]);
  }

  Future<void> _open(ReminiscenceChapterDoc doc) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ReminiscenceChapterDetailPage(weekIndex: doc.weekIndex),
    ));
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final list = _chapters;
    return Scaffold(
      appBar: AppBar(title: const Text(ReminiscenceV2Copy.chaptersPageTitle)),
      body: SafeArea(
        child: list == null
            ? const Center(child: CircularProgressIndicator())
            : list.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(ReminiscenceV2Copy.chaptersEmpty,
                        key: const Key('reminiscence_chapters_empty'),
                        style: theme.textTheme.bodyLarge),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    children: [
                      for (final c in list)
                        Card(
                          key: ValueKey('reminiscence_chapters_week_${c.weekIndex}'),
                          margin: const EdgeInsets.only(bottom: 12),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(20),
                            onTap: () => _open(c),
                            child: Padding(
                              padding: const EdgeInsets.all(18),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    ReminiscenceV2Copy.chapterTitle(c.weekIndex),
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    c.displayText.trim().isEmpty
                                        ? ReminiscenceV2Copy.emptyChapter
                                        : c.displayText,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodyLarge
                                        ?.copyWith(height: 1.5),
                                  ),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: Icon(Icons.chevron_right_rounded,
                                        color: theme.colorScheme.primary),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
      ),
    );
  }
}

/// One chapter: full text, 「改一改」, 「儲存」 (no rating here — it is
/// asked once on the week page).
class ReminiscenceChapterDetailPage extends StatefulWidget {
  const ReminiscenceChapterDetailPage({super.key, required this.weekIndex});
  final int weekIndex;

  @override
  State<ReminiscenceChapterDetailPage> createState() =>
      _ReminiscenceChapterDetailPageState();
}

class _ReminiscenceChapterDetailPageState
    extends State<ReminiscenceChapterDetailPage> {
  ReminiscenceChapterDoc? _doc;
  bool _started = false;
  late ReminiscenceChapterStore _store;
  String? _uid;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _uid = AppSettingsScope.read(context).profile?.uid;
    _store = ReminiscenceV2Stores.chapters(
        available: AuthServiceScope.of(context).available);
    _load();
  }

  Future<void> _load() async {
    final uid = _uid;
    final doc = uid == null ? null : await _store.get(uid, widget.weekIndex);
    if (mounted) setState(() => _doc = doc);
  }

  @override
  Widget build(BuildContext context) {
    final doc = _doc;
    return Scaffold(
      appBar: keyboardCompactAppBar(context,
          title: const CompanionTitle(agentId: AgentRegistry.ahJanAhBakId),
          compactTitle: const CompanionTitle(
              agentId: AgentRegistry.ahJanAhBakId, compact: true)),
      body: SafeArea(
        child: doc == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                children: [
                  ReminiscenceChapterCard(
                    doc: doc,
                    askRating: false,
                    onRated: (_) async {},
                    onSave: (text) async {
                      final uid = _uid;
                      if (uid == null) return;
                      await saveChapterEdit(context,
                          store: _store, uid: uid, doc: doc, edited: text);
                      await _load();
                    },
                  ),
                ],
              ),
      ),
    );
  }
}
