/// 1020c / 1021 — one 小讀本 (bundled HTML) behind `htmlReadersEnabled`.
///
///   §1(3) the page loads `<id>.html` from the App's assets, adds the CSP,
///         the no-zoom viewport, `--fs` (the scale the App actually draws
///         with) and the App's page script, and shows it in a
///         [ReaderSurface] (the WebView).  Only the first load and the
///         App's `peizhu://` links pass; nothing else opens.
///   1021 T-R2 the native top bar (the page hides its own:
///         `data-chrome="app"`).  「‹」 and the system back key first ask
///         the page (`window.peizhuReader.back()`): true = it went from a
///         section back to its contents, stay; false = it is at its
///         contents, close and return to 讀少少.  The title follows the
///         page's `peizhu:view`: at the contents the unit title and
///         「約 n 分鐘」, in a section 「第 i／n 節」 and the unit title.  Top
///         right: the round 「?」 (問下通通, Hybrid only, registry C08:
///         the existing article Q&A with `<id>.txt`); the rule arm keeps
///         the same space empty and has no LLM path.  Hybrid also gets
///         `data-ask="on"` (the page's one line about the 「?」).
///   1021 T-R3 read state: the page reports `peizhuReader.readIds()` with
///         every view change; the App keeps it on this phone per unit
///         ([ReaderReadMarks]) and hands it back next time
///         (`peizhuReader.setRead`).  All sections read = 讀完.
///   §1(4) / T-R4 the action buttons open the App's own pages; 1021 adds
///         `peizhu://cta/chat_siu_yan` → the 小欣 chat (both arms).
///   1021 T-R4b `peizhu://reader/open?id=<id>` (「讀下一篇」) swaps to that
///         unit in this same page (the current unit's read state saved
///         first); back still returns to 讀少少.
///   §1(5) `reader_open` / `reader_section` / `reader_cta` / `reader_close`
///         usage events: ids, a CTA code and seconds, never text.  A swap
///         closes one unit and opens the next.
/// Both arms see the same page otherwise.
library;

import 'package:flutter/material.dart';

import '../../../../core/arm/arm_scope.dart';
import '../../../../core/feature_flags/hybrid_only_mount.dart';
import '../../../../core/usage/usage_event_recorder.dart';
import '../../../../core/usage/usage_events_scope.dart';
import '../../../action_loop/presentation/pages/action_loop_arm_a_page.dart';
import '../../../action_loop/presentation/pages/action_loop_arm_b_page.dart';
import '../../../context/presentation/pages/check_in_page.dart';
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
    this.siuYanChat,
  });

  final ReaderUnit unit;
  final ReaderContentSource source;
  final ReaderSurface surface;
  final ReaderReadMarks readMarks;

  /// 1021 T-R4 (3): the page `peizhu://cta/chat_siu_yan` opens.  Default
  /// [defaultSiuYanChat]; tests pass a stand-in.
  final WidgetBuilder? siuYanChat;

  /// The 小欣 chat: [CheckInPage], the entry every 小欣 card uses — it
  /// picks the page for the arm and the switches (production: the one
  /// 小欣 chat window, both arms).
  static Widget defaultSiuYanChat(BuildContext context) => const CheckInPage();

  /// The round 「?」 (問下通通, Hybrid only).
  static const Key askKey = Key('reader_ask_tung_tung');

  /// The rule arm's empty space where the 「?」 would be.
  static const Key askSpaceKey = Key('reader_ask_space');

  /// The top bar's 「‹」.
  static const Key backKey = Key('reader_back');

  /// The top bar's two title lines.
  static const Key titleKey = Key('reader_title');
  static const Key subtitleKey = Key('reader_subtitle');

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> with WidgetsBindingObserver {
  late ReaderUnit _unit;
  String? _raw;
  String? _prepared;
  bool _failed = false;
  Set<String> _sectionIds = const {};
  final Set<String> _sectionsSent = {};
  int _loadGeneration = 0;

  /// Read sections of the current unit: restored at load, then what the
  /// page reports.  [_restored] is what went into the page (setRead).
  Set<String> _read = {};
  Set<String> _restored = const {};

  /// Where the reader is (null = the contents).
  ReaderViewChanged? _view;

  final ReaderJsBridge _bridge = ReaderJsBridge();

  UsageEventRecorder? _recorder;
  bool _openRecorded = false;
  bool _closed = false;

  /// A back or a swap is being worked out (the page is asked first).
  bool _busy = false;

  /// Time the reader is actually on screen: paused while a page opened
  /// from here (an action button, the 「?」) is on top and while the App
  /// is in the background.  Restarted for each unit.
  final Stopwatch _onScreen = Stopwatch();
  int _coveredBy = 0;
  bool _appVisible = true;

  @override
  void initState() {
    super.initState();
    _unit = widget.unit;
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
      _recorder?.recordReader(UsageEventType.readerOpen, unitId: _unit.id);
    }
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    final unit = _unit;
    try {
      final raw = await widget.source.html(unit.id);
      Map<String, ReaderReadState> marks;
      try {
        marks = await widget.readMarks.load();
      } catch (_) {
        marks = const {};
      }
      if (!mounted || generation != _loadGeneration) return;
      final sections = readerSectionIds(raw);
      final restored = {
        for (final id in marks[unit.id]?.readIds ?? const <String>{})
          if (sections.contains(id)) id,
      };
      setState(() {
        _raw = raw;
        _sectionIds = sections;
        _restored = restored;
        _read = {...restored};
        _prepared = null;
        _view = null;
      });
    } catch (_) {
      if (mounted && generation == _loadGeneration) {
        setState(() => _failed = true);
      }
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

  /// Keep what has been read of the current unit (never removes any).
  Future<void> _saveRead() => widget.readMarks.save(_unit.id,
      readIds: {..._read}, total: _sectionIds.length);

  /// Ask the page for `readIds()` (it may know more than the last
  /// `peizhu:view` told us), then keep it.
  Future<void> _syncReadFromPage() async {
    final ids = await _bridge.readIds();
    if (ids != null) {
      _read.addAll(ids.where(_sectionIds.contains));
    }
    await _saveRead();
  }

  /// `reader_close` for the current unit and its read state, once: when the
  /// page is popped (「‹」, Android back, a pop from elsewhere), or at
  /// dispose if it went some other way.
  void _close() {
    if (_closed) return;
    _closed = true;
    _onScreen.stop();
    _recorder?.recordReader(UsageEventType.readerClose,
        unitId: _unit.id, seconds: _onScreen.elapsed.inSeconds);
    _saveRead();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _close();
    super.dispose();
  }

  /// 1021 T-R2 (2): 「‹」 and the system back key.
  Future<void> _onBack() async {
    if (_busy || _closed || _coveredBy > 0) return;
    _busy = true;
    try {
      // The page goes from a section back to its contents: stay.
      if (await _bridge.back()) return;
      await _syncReadFromPage();
      if (!mounted || _closed) return;
      Navigator.of(context).pop();
    } finally {
      _busy = false;
    }
  }

  /// From the App's page script ([parseReaderMessage]).
  void _onMessage(String raw) {
    final message = parseReaderMessage(raw);
    switch (message) {
      case ReaderSectionReached(:final sectionId):
        // `reader_section`: a well-formed id that occurs in this unit's
        // file, once per opening.
        if (!_sectionIds.contains(sectionId)) return;
        if (!_sectionsSent.add(sectionId)) return;
        _recorder?.recordReader(UsageEventType.readerSection,
            unitId: _unit.id, sectionId: sectionId);
      case ReaderViewChanged():
        if (!message.atContents && !_sectionIds.contains(message.sectionId)) {
          return;
        }
        final before = _read.length;
        _read.addAll(message.readIds.where(_sectionIds.contains));
        if (_read.length != before) _saveRead();
        if (mounted) setState(() => _view = message);
      case null:
        return;
    }
  }

  void _onCta(ReaderCta cta) {
    // A second tap while the first page is still opening: ignore it.
    if (_coveredBy > 0 || _closed || _busy) return;
    _recorder?.recordReader(UsageEventType.readerCta,
        unitId: _unit.id, cta: cta.code);
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
      case ReaderCta.chatSiuYan: // 1021 T-R4 (3): 小欣, both arms
        page = (widget.siuYanChat ?? ReaderPage.defaultSiuYanChat)(context);
    }
    _openOnTop(page);
  }

  /// 1021 T-R4b: 「讀下一篇」 — the same page shows another unit.
  Future<void> _onOpenUnit(String id) async {
    if (_coveredBy > 0 || _closed || _busy || id == _unit.id) return;
    _busy = true;
    try {
      List<ReaderUnit> units;
      try {
        units = await widget.source.units();
      } catch (_) {
        units = const [];
      }
      ReaderUnit? next;
      for (final u in units) {
        if (u.id == id) next = u;
      }
      if (!mounted || _closed) return;
      if (next == null) {
        // Not packaged (tool/check_reader_html.js stops this in CI): say
        // so rather than doing nothing.
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
          content: Text(_isEn(context)
              ? 'This one cannot open right now.'
              : '呢篇暫時打唔開。'),
        ));
        return;
      }
      await _syncReadFromPage();
      if (!mounted || _closed) return;
      // Close the current unit, open the next one.
      _recorder?.recordReader(UsageEventType.readerClose,
          unitId: _unit.id, seconds: _onScreen.elapsed.inSeconds);
      _onScreen
        ..reset()
        ..start();
      _syncClock();
      _sectionsSent.clear();
      setState(() {
        _unit = next!;
        _raw = null;
        _prepared = null;
        _failed = false;
        _view = null;
        _read = {};
        _restored = const {};
        _sectionIds = const {};
      });
      _recorder?.recordReader(UsageEventType.readerOpen, unitId: _unit.id);
      await _load();
    } finally {
      _busy = false;
    }
  }

  Future<void> _ask() async {
    // HybridOnlyMount already hides the button for the rule arm; this
    // keeps the LLM path closed even if something else called it.
    if (!Arm.isA(context) || _coveredBy > 0 || _busy || _raw == null) return;
    final unit = _unit;
    final String text;
    try {
      text = await widget.source.text(unit.id);
    } catch (_) {
      return;
    }
    if (!mounted) return;
    final isEn = _isEn(context);
    await _openOnTop(TungTungPage(
      articleTitle: unit.titleZh,
      articleContext: text,
      articleId: readerQaArticleId(unit.id),
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

  static bool _isEn(BuildContext context) =>
      Localizations.localeOf(context).languageCode == 'en';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEn = _isEn(context);
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
      _prepared ??= prepareReaderHtml(
        _raw!,
        fontScale: MediaQuery.textScalerOf(context).scale(1),
        ask: Arm.isA(context),
        readIds: _restored,
      );
      body = widget.surface.build(
        context,
        ReaderSurfaceRequest(
          html: _prepared!,
          onMessage: _onMessage,
          onCta: _onCta,
          onOpenUnit: _onOpenUnit,
          bridge: _bridge,
          background: theme.colorScheme.surface,
        ),
      );
    }
    final view = _view;
    final inSection = view != null && !view.atContents;
    final total = view != null && view.total > 0 ? view.total : _sectionIds.length;
    final String title;
    final String subtitle;
    if (inSection) {
      title = isEn ? 'Part ${view.index} of $total' : '第 ${view.index}／$total 節';
      subtitle = _unit.titleZh;
    } else {
      title = _unit.titleZh;
      subtitle = isEn ? 'About ${_unit.minutes} min' : '約 ${_unit.minutes} 分鐘';
    }
    // System back (Android key, predictive back) asks the page first; the
    // page is popped only by [_onBack] (or from outside).
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          _close();
        } else {
          _onBack();
        }
      },
      child: Scaffold(
        appBar: _ReaderTopBar(
          title: title,
          subtitle: subtitle,
          onBack: _onBack,
          onAsk: _raw == null ? null : _ask,
        ),
        body: SafeArea(top: false, child: body),
      ),
    );
  }
}

/// 1021 T-R2 — the native top bar: 「‹」, two title lines, the round 「?」
/// (Hybrid) or the same space empty (rule arm).  White, ink #3A3330
/// (`onSurface`), buttons in the App's primary colour.
class _ReaderTopBar extends StatelessWidget implements PreferredSizeWidget {
  const _ReaderTopBar({
    required this.title,
    required this.subtitle,
    required this.onBack,
    required this.onAsk,
  });

  final String title;
  final String subtitle;
  final VoidCallback onBack;
  final VoidCallback? onAsk;

  static const double _side = 64;

  static const double _height = 76;

  @override
  Size get preferredSize => const Size.fromHeight(_height);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final ink = theme.colorScheme.onSurface;
    final primary = theme.colorScheme.primary;
    return AppBar(
      automaticallyImplyLeading: false,
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      foregroundColor: ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      toolbarHeight: _height,
      centerTitle: true,
      titleSpacing: 0,
      leadingWidth: _side,
      shape: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant)),
      leading: Center(
        child: IconButton(
          key: ReaderPage.backKey,
          onPressed: onBack,
          tooltip: isEn ? 'Back' : '返回',
          iconSize: 36,
          color: primary,
          icon: const Icon(Icons.chevron_left_rounded),
        ),
      ),
      title: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              title,
              key: ReaderPage.titleKey,
              maxLines: 1,
              // Two lines must fit the bar at the largest App text (1.30).
              style: theme.textTheme.titleMedium?.copyWith(
                  color: ink,
                  fontSize: 18,
                  height: 1.3,
                  fontWeight: FontWeight.w700),
            ),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              subtitle,
              key: ReaderPage.subtitleKey,
              maxLines: 1,
              style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 14,
                  height: 1.3),
            ),
          ),
        ],
      ),
      actions: [
        SizedBox(
          width: _side,
          child: Center(
            child: HybridOnlyMount(
              featureKey: 'ask_about_this_article',
              fallback: const SizedBox(
                  key: ReaderPage.askSpaceKey, width: 48, height: 48),
              child: _AskButton(onPressed: onAsk),
            ),
          ),
        ),
      ],
    );
  }
}

/// The round 「?」: 問下通通 about this unit (Hybrid only).
class _AskButton extends StatelessWidget {
  const _AskButton({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final primary = theme.colorScheme.primary;
    return Semantics(
      button: true,
      label: isEn ? 'Ask Tung Tung' : '問下通通',
      excludeSemantics: true,
      child: SizedBox(
        width: 48,
        height: 48,
        child: OutlinedButton(
          key: ReaderPage.askKey,
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            shape: const CircleBorder(),
            padding: EdgeInsets.zero,
            minimumSize: const Size(48, 48),
            side: BorderSide(color: primary, width: 1.5),
            backgroundColor: primary.withValues(alpha: 0.10),
            foregroundColor: primary,
          ),
          child: Text(
            '?',
            textScaler: TextScaler.noScaling,
            style: TextStyle(
                fontFamily: theme.textTheme.labelLarge?.fontFamily,
                fontSize: 24,
                height: 1.0,
                fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }
}
