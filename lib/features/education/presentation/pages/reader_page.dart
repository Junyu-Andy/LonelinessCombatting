/// 1020c — one 小讀本 (bundled HTML) behind `htmlReadersEnabled`.
///
///   §1(3) the page loads `<id>.html` from the App's assets, adds the CSP,
///         the no-zoom viewport, `--fs` (the scale the App actually draws
///         with) and the section script, and shows it in a [ReaderSurface]
///         (the WebView).  Only the first load and `peizhu://cta/…` links
///         pass; nothing else opens.  Back (button, Android back, iPhone
///         swipe) pops to the 讀少少 list — the WebView has no history.
///   §1(4) the three action buttons open the App's own pages.
///   §1(5) `reader_open` / `reader_section` / `reader_cta` / `reader_close`
///         usage events: ids, a CTA code and seconds, never text.
///   §1(6) 「問下通通」 at the bottom, Hybrid arm only (registry C08): the
///         existing article Q&A with `<id>.txt` as the article.  The rule
///         arm has no button and no LLM path.
/// Both arms see the same page otherwise.
library;

import 'package:flutter/material.dart';

import '../../../../core/arm/arm_scope.dart';
import '../../../../core/feature_flags/hybrid_only_mount.dart';
import '../../../../core/usage/usage_event_recorder.dart';
import '../../../../core/usage/usage_events_scope.dart';
import '../../../action_loop/presentation/pages/action_loop_arm_a_page.dart';
import '../../../action_loop/presentation/pages/action_loop_arm_b_page.dart';
import '../../../curious_companion/presentation/pages/tung_tung_page.dart';
import '../../../social_suggestions/presentation/pages/social_suggestions_page.dart';
import '../../../thought_exercise/presentation/thought_exercise_page.dart';
import '../../data/reader_html.dart';
import '../../data/reader_qa_prompt.dart';
import '../../data/reader_read_marks.dart';
import '../../data/reader_unit.dart';
import '../reader/reader_surface.dart';

class ReaderPage extends StatefulWidget {
  const ReaderPage({
    super.key,
    required this.unit,
    this.source = const AssetReaderContentSource(),
    this.surface = const WebViewReaderSurface(),
    this.readMarks = const PrefsReaderReadMarks(),
  });

  final ReaderUnit unit;
  final ReaderContentSource source;
  final ReaderSurface surface;
  final ReaderReadMarks readMarks;

  /// The 「問下通通」 button (Hybrid only).
  static const Key askKey = Key('reader_ask_tung_tung');

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> with WidgetsBindingObserver {
  String? _raw;
  String? _prepared;
  bool _failed = false;
  Set<String> _sectionIds = const {};
  final Set<String> _sectionsSent = {};

  UsageEventRecorder? _recorder;
  bool _openRecorded = false;
  bool _closed = false;

  /// Time the reader is actually on screen: paused while a page opened
  /// from here (an action button, 「問下通通」) is on top and while the App
  /// is in the background.
  final Stopwatch _onScreen = Stopwatch();
  int _coveredBy = 0;
  bool _appVisible = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _onScreen.start();
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _recorder ??= UsageEventsScope.maybeOf(context);
    if (!_openRecorded) {
      _openRecorded = true;
      _recorder?.recordReader(UsageEventType.readerOpen,
          unitId: widget.unit.id);
    }
  }

  Future<void> _load() async {
    try {
      final raw = await widget.source.html(widget.unit.id);
      if (!mounted) return;
      setState(() {
        _raw = raw;
        _sectionIds = readerSectionIds(raw);
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appVisible = state == AppLifecycleState.resumed;
    _syncClock();
  }

  void _syncClock() {
    if (_appVisible && _coveredBy == 0) {
      _onScreen.start();
    } else {
      _onScreen.stop();
    }
  }

  /// `reader_close` and the 「讀過」 tick, once: when the page is popped
  /// (back arrow, Android back, iPhone swipe), or at dispose if it went
  /// some other way.
  void _close() {
    if (_closed) return;
    _closed = true;
    _onScreen.stop();
    _recorder?.recordReader(UsageEventType.readerClose,
        unitId: widget.unit.id, seconds: _onScreen.elapsed.inSeconds);
    widget.readMarks.markRead(widget.unit.id);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _close();
    super.dispose();
  }

  /// From the page's section script.  Accepted only if it is a well-formed
  /// id that occurs in this unit's file, once per opening.
  void _onSection(String message) {
    final id = message.trim();
    if (!kReaderIdPattern.hasMatch(id) || !_sectionIds.contains(id)) return;
    if (!_sectionsSent.add(id)) return;
    _recorder?.recordReader(UsageEventType.readerSection,
        unitId: widget.unit.id, sectionId: id);
  }

  void _onCta(ReaderCta cta) {
    // A second tap while the first page is still opening: ignore it.
    if (_coveredBy > 0 || _closed) return;
    _recorder?.recordReader(UsageEventType.readerCta,
        unitId: widget.unit.id, cta: cta.code);
    final Widget page;
    switch (cta) {
      case ReaderCta.smallAction:
        page = const SocialSuggestionsPage(); // 今日嘅小邀請
      case ReaderCta.plan: // 我嘅計劃，新建 — the planner for this arm
        page = Arm.isA(context)
            ? const ActionLoopArmAPage()
            : const ActionLoopArmBPage();
      case ReaderCta.thought:
        page = const ThoughtExercisePage(); // 望一望心入面
    }
    _openOnTop(page);
  }

  Future<void> _ask() async {
    // HybridOnlyMount already hides the button for the rule arm; this
    // keeps the LLM path closed even if something else called it.
    if (!Arm.isA(context) || _coveredBy > 0) return;
    final String text;
    try {
      text = await widget.source.text(widget.unit.id);
    } catch (_) {
      return;
    }
    if (!mounted) return;
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    await _openOnTop(TungTungPage(
      articleTitle: widget.unit.titleZh,
      articleContext: text,
      articleId: readerQaArticleId(widget.unit.id),
      articleContextHeader: isEn ? kReaderQaHeaderEn : kReaderQaHeaderZh,
    ));
  }

  Future<void> _openOnTop(Widget page) async {
    _coveredBy++;
    _syncClock();
    try {
      await Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => page));
    } finally {
      _coveredBy--;
      if (mounted) _syncClock();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final Widget body;
    if (_failed) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            isEn ? 'This one cannot open right now.' : '呢篇暫時打唔開。',
            style: theme.textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
        ),
      );
    } else if (_raw == null) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      // `--fs` = the scale the App draws its own text with (five 字號
      // levels; appFontScaleOnlyEnabled already applied in app.dart).
      _prepared ??= prepareReaderHtml(_raw!,
          fontScale: MediaQuery.textScalerOf(context).scale(1));
      body = widget.surface.build(
        context,
        ReaderSurfaceRequest(
          html: _prepared!,
          onSection: _onSection,
          onCta: _onCta,
          background: theme.colorScheme.surface,
        ),
      );
    }
    // Back (app bar arrow, Android back, iPhone swipe) simply pops to the
    // 讀少少 list: the WebView never navigates, so it has no history.
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _close();
      },
      child: Scaffold(
        appBar: AppBar(title: Text(widget.unit.titleZh)),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(child: body),
              HybridOnlyMount(
                featureKey: 'ask_about_this_article',
                child: _AskBar(onPressed: _raw == null ? null : _ask),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 「問下通通」 — same style as the articles' 「問通通呢篇」 button.
class _AskBar extends StatelessWidget {
  const _AskBar({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: OutlinedButton.icon(
        key: ReaderPage.askKey,
        onPressed: onPressed,
        icon: const Icon(Icons.chat_bubble_outline),
        label: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text(
            isEn ? 'Ask Tung Tung' : '問下通通', // DRAFT (1020c §1(6))
            style: const TextStyle(fontSize: 18),
          ),
        ),
      ),
    );
  }
}
