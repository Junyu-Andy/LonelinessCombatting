/// 1020d section 6 (6) / section 7 — the chapter as the elder sees it, the
/// same in both arms: 「第 N 章：{主題}」, the text, then (once per chapter
/// version) the three ratings one at a time, then 「改一改」 and 「儲存」.
///
/// The rating reuses the Brief PR scale ([BriefPrScale]: 1–7 as numbers
/// only, words under 1 and 7); 「唔評住」 skips the current question.  The
/// card only collects; the page writes (`reminiscence_chapter_ratings`,
/// `editedText` / `editRatio`).
library;

import 'package:flutter/material.dart';

import '../../../brief_pr/presentation/pages/brief_pr_flow_page.dart';
import '../../data/reminiscence_v2_copy.dart';
import '../../data/reminiscence_v2_models.dart';

/// What the three answers were: score (null = 唔評住) per item key.
typedef ChapterRatingResult = ({
  Map<String, int?> scores,
  Map<String, bool> skipped,
});

class ReminiscenceChapterCard extends StatefulWidget {
  const ReminiscenceChapterCard({
    super.key,
    required this.doc,
    required this.askRating,
    required this.onRated,
    required this.onSave,
    this.showReadyBanner = false,
  });

  final ReminiscenceChapterDoc doc;

  /// The rating comes before 改一改 / 儲存, once per chapter version.
  final bool askRating;
  final Future<void> Function(ChapterRatingResult result) onRated;

  /// 「儲存」 with the text as it is now (edited or not).
  final Future<void> Function(String text) onSave;

  /// 「第 N 章整理好喇」 above the title (a new chapter not yet rated).
  final bool showReadyBanner;

  @override
  State<ReminiscenceChapterCard> createState() =>
      _ReminiscenceChapterCardState();
}

class _ReminiscenceChapterCardState extends State<ReminiscenceChapterCard> {
  int _index = 0;
  final Map<String, int?> _scores = {};
  final Map<String, bool> _skipped = {};
  bool _ratingSent = false;
  bool _editing = false;
  bool _saving = false;
  bool _saved = false;
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.doc.displayText);

  @override
  void didUpdateWidget(covariant ReminiscenceChapterCard old) {
    super.didUpdateWidget(old);
    if (old.doc.requestId != widget.doc.requestId) {
      // A new chapter (重新整理): rate again, nothing edited yet.
      _index = 0;
      _scores.clear();
      _skipped.clear();
      _ratingSent = false;
      _editing = false;
      _saved = false;
      _ctrl.text = widget.doc.displayText;
    } else if (!_editing && old.doc.displayText != widget.doc.displayText) {
      _ctrl.text = widget.doc.displayText;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  bool get _rating => widget.askRating && !_ratingSent;
  ReminiscenceV2RatingItem get _item => ReminiscenceV2Copy.ratingItems[_index];
  bool get _isLast => _index == ReminiscenceV2Copy.ratingItems.length - 1;

  Future<void> _nextRating({required bool skip}) async {
    final key = _item.key;
    if (skip) {
      _scores[key] = null;
      _skipped[key] = true;
    } else {
      if (_scores[key] == null) return;
      _skipped[key] = false;
    }
    if (!_isLast) {
      setState(() => _index++);
      return;
    }
    setState(() => _ratingSent = true);
    await widget.onRated((
      scores: {
        for (final i in ReminiscenceV2Copy.ratingItems) i.key: _scores[i.key],
      },
      skipped: {
        for (final i in ReminiscenceV2Copy.ratingItems)
          i.key: _skipped[i.key] ?? true,
      },
    ));
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await widget.onSave(_ctrl.text.trim());
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
          _saved = true;
          _editing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final doc = widget.doc;
    final text = doc.displayText.trim().isEmpty
        ? ReminiscenceV2Copy.emptyChapter
        : doc.displayText;
    return Card(
      key: const Key('reminiscence_chapter_card'),
      margin: const EdgeInsets.symmetric(vertical: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.showReadyBanner)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Icon(Icons.auto_stories_outlined,
                        color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        ReminiscenceV2Copy.chapterReady(doc.weekIndex),
                        key: const Key('reminiscence_chapter_ready'),
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Text(
              ReminiscenceV2Copy.chapterTitle(doc.weekIndex),
              key: const Key('reminiscence_chapter_title'),
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                fontSize: 22,
              ),
            ),
            const SizedBox(height: 12),
            if (_editing)
              TextField(
                key: const Key('reminiscence_chapter_edit_field'),
                controller: _ctrl,
                minLines: 6,
                maxLines: null,
                scrollPadding: const EdgeInsets.only(bottom: 160),
                style: const TextStyle(fontSize: 19, height: 1.7),
                decoration:
                    const InputDecoration(border: OutlineInputBorder()),
              )
            else
              Text(
                text,
                key: const Key('reminiscence_chapter_text'),
                style: const TextStyle(fontSize: 19, height: 1.7),
              ),
            const SizedBox(height: 16),
            if (_rating) _ratingPanel(theme) else _editButtons(),
          ],
        ),
      ),
    );
  }

  Widget _ratingPanel(ThemeData theme) {
    final item = _item;
    final total = ReminiscenceV2Copy.ratingItems.length;
    return Container(
      key: ValueKey('reminiscence_rating_${item.key}'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${ReminiscenceV2Copy.ratingStem}　${_index + 1}/$total',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            item.question,
            key: const Key('reminiscence_rating_question'),
            style: theme.textTheme.titleMedium?.copyWith(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          BriefPrScale(
            value: _scores[item.key],
            low: item.low,
            high: item.high,
            keyPrefix: 'reminiscence_rating_option_',
            onSelect: (v) => setState(() => _scores[item.key] = v),
          ),
          const SizedBox(height: 14),
          FilledButton(
            key: const Key('reminiscence_rating_next'),
            onPressed: _scores[item.key] == null
                ? null
                : () => _nextRating(skip: false),
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 52),
            ),
            child: Text(
              _isLast
                  ? ReminiscenceV2Copy.ratingDone
                  : ReminiscenceV2Copy.ratingNext,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: TextButton(
              key: const Key('reminiscence_rating_skip'),
              onPressed: () => _nextRating(skip: true),
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              child: const Text(ReminiscenceV2Copy.ratingSkip,
                  style: TextStyle(fontSize: 17)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _editButtons() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            key: const Key('reminiscence_chapter_edit'),
            onPressed: _editing || _saving
                ? null
                : () => setState(() {
                      _editing = true;
                      _saved = false;
                    }),
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 52)),
            child: const Text(ReminiscenceV2Copy.editLabel,
                style: TextStyle(fontSize: 18)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton(
            key: const Key('reminiscence_chapter_save'),
            onPressed: _saving || (_saved && !_editing) ? null : _save,
            style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
            child: Text(
              _saved && !_editing
                  ? ReminiscenceV2Copy.savedLabel
                  : ReminiscenceV2Copy.saveLabel,
              style: const TextStyle(fontSize: 18),
            ),
          ),
        ),
      ],
    );
  }
}

/// 「整理緊…」 (Hybrid, while the server writes the chapter) or the failed
/// note.
class ReminiscenceChapterPending extends StatelessWidget {
  const ReminiscenceChapterPending({
    super.key,
    required this.weekIndex,
    this.failed = false,
  });

  final int weekIndex;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: Key(failed
          ? 'reminiscence_chapter_failed'
          : 'reminiscence_chapter_generating'),
      margin: const EdgeInsets.symmetric(vertical: 10),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              ReminiscenceV2Copy.chapterTitle(weekIndex),
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                fontSize: 22,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!failed)
                  const Padding(
                    padding: EdgeInsets.only(top: 4, right: 12),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                Expanded(
                  child: Text(
                    failed
                        ? ReminiscenceV2Copy.failed
                        : ReminiscenceV2Copy.generating,
                    style: const TextStyle(fontSize: 18, height: 1.5),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
