/// 1020 D / E — shared plumbing for page 1 「睇今日」 (two-page layout,
/// mood row): one refresh signal and the seams tests and screenshots use.
/// The App puts no [HomeV2Scope] in the tree, so every widget falls back
/// to its Firestore / shared_preferences default.
library;

import 'package:flutter/widgets.dart';

import '../../../core/session/session_entry_surface.dart';
import '../../context/presentation/pages/check_in_page.dart';
import '../../action_loop/presentation/pages/action_loop_landing.dart';
import '../../context/presentation/pages/siu_yan_chat_page.dart';
import '../../social_suggestions/presentation/pages/social_suggestions_page.dart';
import '../../weekly_bundle/data/weekly_bundle.dart';
import '../data/mood_row_copy.dart';
import '../data/mood_row_store.dart';
import '../data/small_action_row_store.dart';

class HomeV2Scope extends InheritedWidget {
  const HomeV2Scope({
    super.key,
    required super.child,
    this.checkedInToday,
    this.daysSinceLastCheckIn,
    this.moodStore,
    this.weeklyStore,
    this.clock,
    this.moodChatPage,
    this.checkInPage,
    this.smallActionStore,
    this.smallActionPage,
    this.myPlansPage,
  });

  /// Today's check-in done?  Default: the `check_in_submitted` event.
  final Future<bool> Function(String uid)? checkedInToday;

  /// Days since the last check-in (null = never).  Default: the event.
  final Future<int?> Function(String uid)? daysSinceLastCheckIn;

  final MoodRowStore? moodStore;
  final WeeklyBundleStore Function(String uid)? weeklyStore;
  final DateTime Function()? clock;

  /// The page M7 / M8 open.  Default: [SiuYanChatPage] with the entry.
  final Widget Function(MoodChatEntry entry)? moodChatPage;

  /// The page the check-in row opens.  Default: [CheckInPage].
  final Widget Function()? checkInPage;

  /// 1020m 第二节 — the small-action row's plans and marks.  Default:
  /// [DefaultSmallActionRowStore] (Firestore + shared_preferences).
  final SmallActionRowStore? smallActionStore;

  /// The page 「今日想做啲咩小行動？」 opens.  Default:
  /// [SocialSuggestionsPage] (今日小行動, the 做啲嘢 page's first card).
  final Widget Function()? smallActionPage;

  /// 1020n: the page 「仲有 N 個計劃」 opens.  Default:
  /// [ActionLoopLandingPage] (我嘅計劃).
  final Widget Function()? myPlansPage;

  static HomeV2Scope? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<HomeV2Scope>();

  static DateTime now(BuildContext context) =>
      (maybeOf(context)?.clock ?? DateTime.now)();

  static Widget buildMoodChat(BuildContext context, MoodChatEntry entry) =>
      maybeOf(context)?.moodChatPage?.call(entry) ??
      SiuYanChatPage(
        moodEntry: entry,
        lowMoodEntry: entry.lowOpener,
      );

  static Widget buildCheckIn(BuildContext context) =>
      maybeOf(context)?.checkInPage?.call() ?? const CheckInPage();

  static Widget buildSmallActionPage(BuildContext context) =>
      maybeOf(context)?.smallActionPage?.call() ??
      const SocialSuggestionsPage();

  static Widget buildMyPlansPage(BuildContext context) =>
      maybeOf(context)?.myPlansPage?.call() ?? const ActionLoopLandingPage();

  @override
  bool updateShouldNotify(HomeV2Scope oldWidget) => false;
}

/// Bumped when page 1 comes back from a page it opened (check-in, 小欣's
/// chat, the questionnaire), so every row re-reads what it shows.
class HomeV2Refresh {
  HomeV2Refresh._();

  static final ChangeNotifier changes = _Notifier();

  static void bump() => (changes as _Notifier).bump();
}

class _Notifier extends ChangeNotifier {
  void bump() => notifyListeners();
}

/// 1020e 一.(9) — marks which home page a widget sits on (page 1 「睇今日」
/// or page 2 「搵人傾」 of the two-page layout).  [push] opens a page from
/// there with [SessionEntrySurface] set, so a session started in it
/// records `entrySurface`.  Absent (old layout, other pages): plain push,
/// nothing recorded.
class HomeSurfaceScope extends InheritedWidget {
  const HomeSurfaceScope({
    super.key,
    required this.surface,
    required super.child,
  });

  /// [SessionEntrySurface.page1] or [SessionEntrySurface.page2].
  final String surface;

  static String? of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<HomeSurfaceScope>()?.surface;

  /// `Navigator.push` from a home page, with the page recorded.
  static Future<T?> push<T>(BuildContext context, Route<T> route) {
    final nav = Navigator.of(context);
    return SessionEntrySurface.during<T>(of(context), () => nav.push(route));
  }

  @override
  bool updateShouldNotify(HomeSurfaceScope oldWidget) =>
      surface != oldWidget.surface;
}
