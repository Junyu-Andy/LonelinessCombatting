// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'With You';

  @override
  String get homeTab => 'Home';

  @override
  String get contextTab => 'About You';

  @override
  String get actionTab => 'Activities';

  @override
  String get followUpTab => 'Follow-up';

  @override
  String get settingsTab => 'Self';

  @override
  String get homeSubtitle => 'This is the home overview for the demo.';

  @override
  String get homeStructureHint =>
      'Four modules: Trust → Context → Action → Follow-up.';

  @override
  String get contextSubtitle =>
      'Your details, recent state, follow-up cadence.';

  @override
  String get actionSubtitle => 'Pick something pleasant and just start.';

  @override
  String get followUpSubtitle => 'Reminders, progress, pacing.';

  @override
  String get settingsSubtitle => 'Language, boundaries, about.';

  @override
  String get developerCredit =>
      'Built by HKU Department of Data and Systems Engineering';

  @override
  String get developerCreditShort => 'HKU DSE';

  @override
  String get onboardingWelcomeTitle => 'A calmer start';

  @override
  String get onboardingWelcomeBody => 'A quick look at the app\'s structure.';

  @override
  String get onboardingHelpTitle => 'How it can help';

  @override
  String get onboardingHelpBody =>
      'Check-ins  •  social map  •  small steps  •  follow-up.';

  @override
  String get onboardingBoundaryTitle => 'System boundaries';

  @override
  String get onboardingBoundaryBody => 'Structure and suggestions only.';

  @override
  String get onboardingBoundaryItemOne => 'Reflect & prepare';

  @override
  String get onboardingBoundaryItemTwo => 'Small concrete actions';

  @override
  String get onboardingBoundaryItemThree => '❌ Not for crisis support';

  @override
  String get onboardingStartTitle => 'Enter the demo';

  @override
  String get onboardingStartBody => 'Explore at your own pace.';

  @override
  String get back => 'Back';

  @override
  String get next => 'Next';

  @override
  String get enterDemo => 'Enter Demo';

  @override
  String get tabToday => 'Today';

  @override
  String get tabMyStory => 'Talk';

  @override
  String get tabMe => 'Do';

  @override
  String get greetingMorning => 'Good morning';
  @override
  String get greetingNoon => 'Good noon';
  @override
  String get greetingAfternoon => 'Good afternoon';
  @override
  String get greetingEvening => 'Good evening';
  @override
  String get greetingNight => "It's late — take it easy";

  @override
  String get todayCheckInTitle => "Today's Check-in";
  @override
  String get todayCheckInSubtitle => 'A minute to log how you feel.';
  @override
  String get todayMicroReflection => 'A reflection';
  @override
  String get todayMicroInvitation => "Today's invitation";
  @override
  String get todayActivePlanLabel => "Today's plan";
  @override
  String get todayActivePlanEmpty => 'No plan for today.';

  @override
  String myStoryWeekProgress(int current, int total) =>
      'Week $current of $total';
  @override
  String myStoryWeekTitle(int n) => 'Week $n';
  @override
  String get myStorySessionNotStarted =>
      "This week's session hasn't started";
  @override
  String get myStorySessionInProgress => 'Continue last session';
  @override
  String get myStorySessionCompleted => 'Done this week';
  @override
  String get myStoryStartCta => 'Start';
  @override
  String get myStoryContinueCta => 'Continue';
  @override
  String get myStoryRereadCta => 'Re-read';
  @override
  String get myStoryTimelineHeader => 'Your story so far';
  @override
  String get myStoryHistoryHeader => 'Past sessions';
  @override
  String get myStoryHistoryEmpty => 'No completed sessions yet.';

  @override
  String get meItemProgress => 'Your week';
  @override
  String get meItemActionLoop => 'Follow-up plans';
  @override
  String get meItemArticles => 'Read a little';
  @override
  String get meItemCrisis => 'Crisis support';
  @override
  String get meItemProfile => 'My profile';
  @override
  String get meItemProgressSubtitle =>
      'Mood and social moments across the week';
  @override
  String get meItemActionLoopSubtitle => 'Track the small steps you set';
  @override
  String get meItemArticlesSubtitle =>
      'Short reads on loneliness and well-being';
  @override
  String get meItemCrisisSubtitle => 'Who to reach in an emergency';
  @override
  String get meItemProfileSubtitle => 'Update your details';

  @override
  String get safetyPillLow => 'Talk now';
  @override
  String get safetyPillModerate => 'Need support?';
  @override
  String get safetyPillAcute => 'Crisis line';
}
