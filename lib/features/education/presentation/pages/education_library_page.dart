import 'package:flutter/material.dart';

import '../../../../core/feature_flags/remote_feature_flags.dart';
import '../../data/education_library.dart';
import '../../data/reader_read_marks.dart';
import '../../data/reader_unit.dart';
import '../reader/reader_surface.dart';
import 'education_article_page.dart';
import 'reader_page.dart';
import '../../../../core/session/chat_session_recorder.dart';

/// M8 library landing — identical in both arms (spec: library content
/// is identical; only the "Ask me about this" dialogue is Arm A).
///
/// 1020c §2 — with `htmlReadersEnabled` on and at least one packaged
/// unit, a 「小讀本」 section sits on top (title, about how many minutes,
/// a tick once read on this phone); the 15 articles below are unchanged.
/// Switch off, or no unit: the page is exactly as before.  Both arms see
/// the same list.
class EducationLibraryPage extends StatefulWidget {
  const EducationLibraryPage({
    super.key,
    this.readerSource = const AssetReaderContentSource(),
    this.readerSurface = const WebViewReaderSurface(),
    this.readMarks = const PrefsReaderReadMarks(),
  });

  /// 1020c: where the 小讀本 come from, how they are shown, where the
  /// 「讀過」 ticks live.  Tests pass fakes.
  final ReaderContentSource readerSource;
  final ReaderSurface readerSurface;
  final ReaderReadMarks readMarks;

  @override
  State<EducationLibraryPage> createState() => _EducationLibraryPageState();
}

class _EducationLibraryPageState extends State<EducationLibraryPage> {
  List<ReaderUnit> _units = const [];
  Set<String> _read = const {};

  @override
  void initState() {
    super.initState();
    if (RemoteFeatureFlags.current.htmlReadersEnabled) _loadReaders();
  }

  Future<void> _loadReaders() async {
    final units = await widget.readerSource.units();
    final read = await widget.readMarks.load();
    if (!mounted) return;
    setState(() {
      _units = units;
      _read = read;
    });
  }

  Future<void> _openReader(ReaderUnit unit) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ReaderPage(
        unit: unit,
        source: widget.readerSource,
        surface: widget.readerSurface,
        readMarks: widget.readMarks,
      ),
    ));
    // The reader marks itself read on this phone when it closes
    // (reader_close); show the tick now.
    if (mounted) setState(() => _read = {..._read, unit.id});
  }

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);
    final showReaders =
        RemoteFeatureFlags.current.htmlReadersEnabled && _units.isNotEmpty;
    // M-7 — tool session: enter = start, leave = end.
    return ToolSessionScope(
      toolId: 'education',
      child: Scaffold(
      appBar: AppBar(title: Text(isEn ? 'Read a little' : '讀少少')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            if (showReaders) ...[
              _ReadersSection(
                units: _units,
                read: _read,
                onOpen: _openReader,
              ),
              const SizedBox(height: 12),
              Divider(color: theme.colorScheme.outlineVariant),
              const SizedBox(height: 12),
            ],
            Text(
              isEn
                  ? 'Short pieces, plain language. Take what helps, skip '
                      'the rest.'
                  : '每篇短短，平實啲講。睇啱嘅，唔啱就過。',
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
            // Research Review v2 Item 1: filter by enabled flag so individual
            // articles can be hidden without a code push during Phase A.
            for (final a in EducationLibrary.articles.where((a) => a.enabled))
              _ArticleCard(
                article: a,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => EducationArticlePage(article: a),
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

/// 1020c §2(1)/(3) — the 小讀本 section.  Copy is a DRAFT for Junyu.
class _ReadersSection extends StatelessWidget {
  const _ReadersSection({
    required this.units,
    required this.read,
    required this.onOpen,
  });

  final List<ReaderUnit> units;
  final Set<String> read;
  final ValueChanged<ReaderUnit> onOpen;

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);
    return Column(
      key: const Key('readers_section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          isEn ? 'Little readers' : '小讀本',
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: 6),
        Text(
          isEn
              ? 'One every few days is plenty — no need to read them all '
                  'at once.'
              : '每隔幾日睇一篇就得，唔使一次睇晒。',
          style: theme.textTheme.bodyLarge,
        ),
        const SizedBox(height: 14),
        for (final u in units)
          _ReaderCard(
            unit: u,
            read: read.contains(u.id),
            onTap: () => onOpen(u),
          ),
      ],
    );
  }
}

class _ReaderCard extends StatelessWidget {
  const _ReaderCard({
    required this.unit,
    required this.read,
    required this.onTap,
  });

  final ReaderUnit unit;
  final bool read;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        key: Key('reader_card_${unit.id}'),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Icon(Icons.auto_stories_outlined,
                    size: 28, color: theme.colorScheme.primary),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(unit.titleZh, style: theme.textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text(
                        isEn
                            ? 'About ${unit.minutes} min'
                            : '大約 ${unit.minutes} 分鐘',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (read) ...[
                  const SizedBox(width: 8),
                  Icon(
                    Icons.check_circle_rounded,
                    key: Key('reader_read_${unit.id}'),
                    color: theme.colorScheme.primary,
                    semanticLabel: isEn ? 'Read' : '讀過',
                  ),
                ],
                const SizedBox(width: 4),
                Icon(Icons.chevron_right_rounded,
                    color: theme.colorScheme.primary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ArticleCard extends StatelessWidget {
  final EducationArticle article;
  final VoidCallback onTap;
  const _ArticleCard({required this.article, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Icon(Icons.menu_book_outlined,
                    size: 28, color: theme.colorScheme.primary),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    isEn ? article.titleEn : article.titleZh,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                Icon(Icons.chevron_right_rounded,
                    color: theme.colorScheme.primary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
