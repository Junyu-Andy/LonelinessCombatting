import 'package:flutter/material.dart';

import '../../data/reader_read_marks.dart';
import '../../data/reader_unit.dart';
import '../reader/reader_icons.dart';
import '../reader/reader_surface.dart';
import 'reader_page.dart';
import '../../../../core/session/chat_session_recorder.dart';

/// M8 library landing — identical in both arms (spec: library content
/// is identical; only the 「?」 question to 通通 inside a 小讀本 is Arm A).
///
/// 10/21 (decisions-log 133 (1)) — the page lists only the 14 packaged
/// 小讀本; the 15 old articles and their article page are gone, and the
/// list no longer depends on `htmlReadersEnabled`.  No packaged unit:
/// nothing below the title.  Both arms see the same list.
///
/// 1021 T-R1 — the units are grouped by the manifest's `part`, each group
/// headed 「第一部分：」 + `partTitleZh`; each row: the manifest's Material
/// icon on the left, the title, 「約 n 分鐘」 on the right, and 「✓ 讀完」
/// (an icon and text, no emoji) once every section has been read on this
/// phone (T-R3).
class EducationLibraryPage extends StatefulWidget {
  const EducationLibraryPage({
    super.key,
    this.readerSource = const AssetReaderContentSource(),
    this.readerSurface = const WebViewReaderSurface(),
    this.readMarks = const PrefsReaderReadMarks(),
  });

  /// 1020c: where the 小讀本 come from, how they are shown, where the
  /// read state lives.  Tests pass fakes.
  final ReaderContentSource readerSource;
  final ReaderSurface readerSurface;
  final ReaderReadMarks readMarks;

  @override
  State<EducationLibraryPage> createState() => _EducationLibraryPageState();
}

class _EducationLibraryPageState extends State<EducationLibraryPage> {
  List<ReaderUnit> _units = const [];
  Map<String, ReaderReadState> _read = const {};

  @override
  void initState() {
    super.initState();
    _loadReaders();
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
    // The reader keeps what was read (maybe of several units, 「讀下一
    // 篇」); show the ticks now.
    final read = await widget.readMarks.load();
    if (mounted) setState(() => _read = read);
  }

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);
    // M-7 — tool session: enter = start, leave = end.
    return ToolSessionScope(
      toolId: 'education',
      child: Scaffold(
      // 10/21: the page title stands apart from the content — white bar, a
      // line under it, bold, like the 小讀本 reader's own top bar.
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        shape: Border(
            bottom: BorderSide(color: theme.colorScheme.outlineVariant)),
        title: Text(
          isEn ? 'Read a little' : '讀少少',
          key: const Key('education_library_title'),
          style: theme.appBarTheme.titleTextStyle
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            if (_units.isNotEmpty)
              _ReadersSection(
                units: _units,
                read: _read,
                onOpen: _openReader,
              ),
          ],
        ),
      ),
      ),
    );
  }
}

/// 1021 T-R1 (1): 「第一部分：認識孤單」 — the part number in Chinese
/// numerals (一 … 十, then digits) and the manifest's `partTitleZh`.
String readerPartHeading(int part, String? partTitleZh, {bool en = false}) {
  const numerals = ['一', '二', '三', '四', '五', '六', '七', '八', '九', '十'];
  final n = part >= 1 && part <= numerals.length ? numerals[part - 1] : '$part';
  final title = partTitleZh ?? '';
  if (en) return title.isEmpty ? 'Part $part' : 'Part $part: $title';
  return title.isEmpty ? '第$n部分' : '第$n部分：$title';
}

/// The units in list order, grouped by part (units without a part first,
/// without a heading).  Parts in ascending order; within a part, the
/// manifest order.
List<(int?, String?, List<ReaderUnit>)> groupReaderUnits(
    List<ReaderUnit> units) {
  final groups = <int?, List<ReaderUnit>>{};
  final titles = <int?, String?>{};
  for (final u in units) {
    groups.putIfAbsent(u.part, () => []).add(u);
    titles[u.part] ??= u.partTitleZh;
  }
  final keys = groups.keys.toList()
    ..sort((a, b) => a == null ? -1 : (b == null ? 1 : a.compareTo(b)));
  return [for (final k in keys) (k, titles[k], groups[k]!)];
}

/// 1020c §2(1)/(3) — the 小讀本 section.  1021 T-R1: grouped by part.
class _ReadersSection extends StatelessWidget {
  const _ReadersSection({
    required this.units,
    required this.read,
    required this.onOpen,
  });

  final List<ReaderUnit> units;
  final Map<String, ReaderReadState> read;
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
          style: theme.textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          isEn
              ? 'One every few days is plenty — no need to read them all '
                  'at once.'
              : '每隔幾日睇一篇就得，唔使一次睇晒。',
          style: theme.textTheme.bodyLarge,
        ),
        for (final (part, partTitle, items) in groupReaderUnits(units)) ...[
          const SizedBox(height: 16),
          if (part != null) ...[
            Semantics(
              header: true,
              child: Text(
                readerPartHeading(part, partTitle, en: isEn),
                key: Key('reader_part_$part'),
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
          for (final u in items)
            _ReaderCard(
              unit: u,
              done: read[u.id]?.done ?? false,
              onTap: () => onOpen(u),
            ),
        ],
      ],
    );
  }
}

class _ReaderCard extends StatelessWidget {
  const _ReaderCard({
    required this.unit,
    required this.done,
    required this.onTap,
  });

  final ReaderUnit unit;
  final bool done;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        key: Key('reader_card_${unit.id}'),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Row(
              children: [
                Icon(readerIconFor(unit.icon),
                    key: Key('reader_icon_${unit.id}'),
                    size: 30, color: theme.colorScheme.primary),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(unit.titleZh, style: theme.textTheme.titleMedium),
                      if (done) ...[
                        const SizedBox(height: 6),
                        // Shrinks rather than overflow on a narrow phone at
                        // the largest text.
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: _DoneBadge(key: Key('reader_done_${unit.id}')),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  isEn ? 'About ${unit.minutes} min' : '約 ${unit.minutes} 分鐘',
                  key: Key('reader_minutes_${unit.id}'),
                  style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 「✓ 讀完」 — a check icon and the word, no emoji (T-R1 (4)).
class _DoneBadge extends StatelessWidget {
  const _DoneBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    return Semantics(
      label: isEn ? 'Finished' : '讀完',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 2, 10, 2),
        decoration: BoxDecoration(
          color: primary.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_rounded, size: 18, color: primary),
            const SizedBox(width: 4),
            Text(
              isEn ? 'Finished' : '讀完',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: primary, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}
