import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
    Locale.fromSubtags(
      languageCode: 'zh',
      countryCode: 'HK',
      scriptCode: 'Hant',
    ),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'With You'**
  String get appTitle;

  /// No description provided for @homeTab.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get homeTab;

  /// No description provided for @contextTab.
  ///
  /// In en, this message translates to:
  /// **'About You'**
  String get contextTab;

  /// No description provided for @actionTab.
  ///
  /// In en, this message translates to:
  /// **'Activities'**
  String get actionTab;

  /// No description provided for @followUpTab.
  ///
  /// In en, this message translates to:
  /// **'Follow-up'**
  String get followUpTab;

  /// No description provided for @settingsTab.
  ///
  /// In en, this message translates to:
  /// **'Self'**
  String get settingsTab;

  /// No description provided for @homeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'This is the home overview for the demo.'**
  String get homeSubtitle;

  /// No description provided for @homeStructureHint.
  ///
  /// In en, this message translates to:
  /// **'Four modules: Trust → Context → Action → Follow-up.'**
  String get homeStructureHint;

  /// No description provided for @contextSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Your details, recent state, follow-up cadence.'**
  String get contextSubtitle;

  /// No description provided for @actionSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Pick something pleasant and just start.'**
  String get actionSubtitle;

  /// No description provided for @followUpSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Reminders, progress, pacing.'**
  String get followUpSubtitle;

  /// No description provided for @settingsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Language, boundaries, about.'**
  String get settingsSubtitle;

  /// No description provided for @developerCredit.
  ///
  /// In en, this message translates to:
  /// **'Built by HKU Department of Data and Systems Engineering'**
  String get developerCredit;

  /// No description provided for @developerCreditShort.
  ///
  /// In en, this message translates to:
  /// **'HKU DSE'**
  String get developerCreditShort;

  /// No description provided for @onboardingWelcomeTitle.
  ///
  /// In en, this message translates to:
  /// **'A calmer start'**
  String get onboardingWelcomeTitle;

  /// No description provided for @onboardingWelcomeBody.
  ///
  /// In en, this message translates to:
  /// **'A quick look at the app\'s structure.'**
  String get onboardingWelcomeBody;

  /// No description provided for @onboardingHelpTitle.
  ///
  /// In en, this message translates to:
  /// **'How it can help'**
  String get onboardingHelpTitle;

  /// No description provided for @onboardingHelpBody.
  ///
  /// In en, this message translates to:
  /// **'Check-ins  •  social map  •  small steps  •  follow-up.'**
  String get onboardingHelpBody;

  /// No description provided for @onboardingBoundaryTitle.
  ///
  /// In en, this message translates to:
  /// **'System boundaries'**
  String get onboardingBoundaryTitle;

  /// No description provided for @onboardingBoundaryBody.
  ///
  /// In en, this message translates to:
  /// **'Structure and suggestions only.'**
  String get onboardingBoundaryBody;

  /// No description provided for @onboardingBoundaryItemOne.
  ///
  /// In en, this message translates to:
  /// **'Reflect & prepare'**
  String get onboardingBoundaryItemOne;

  /// No description provided for @onboardingBoundaryItemTwo.
  ///
  /// In en, this message translates to:
  /// **'Small concrete actions'**
  String get onboardingBoundaryItemTwo;

  /// No description provided for @onboardingBoundaryItemThree.
  ///
  /// In en, this message translates to:
  /// **'❌ Not for crisis support'**
  String get onboardingBoundaryItemThree;

  /// No description provided for @onboardingStartTitle.
  ///
  /// In en, this message translates to:
  /// **'Enter the demo'**
  String get onboardingStartTitle;

  /// No description provided for @onboardingStartBody.
  ///
  /// In en, this message translates to:
  /// **'Explore at your own pace.'**
  String get onboardingStartBody;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @next.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get next;

  /// No description provided for @enterDemo.
  ///
  /// In en, this message translates to:
  /// **'Enter Demo'**
  String get enterDemo;

  /// No description provided for @tabToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get tabToday;

  /// No description provided for @tabMyStory.
  ///
  /// In en, this message translates to:
  /// **'Talk'**
  String get tabMyStory;

  /// No description provided for @tabMe.
  ///
  /// In en, this message translates to:
  /// **'Do'**
  String get tabMe;

  /// No description provided for @greetingMorning.
  ///
  /// In en, this message translates to:
  /// **'Good morning'**
  String get greetingMorning;

  /// No description provided for @greetingAfternoon.
  ///
  /// In en, this message translates to:
  /// **'Good afternoon'**
  String get greetingAfternoon;

  /// No description provided for @greetingEvening.
  ///
  /// In en, this message translates to:
  /// **'Good evening'**
  String get greetingEvening;

  /// No description provided for @greetingNight.
  ///
  /// In en, this message translates to:
  /// **'It\'s late now'**
  String get greetingNight;

  /// No description provided for @greetingTagline.
  ///
  /// In en, this message translates to:
  /// **'With You is here.'**
  String get greetingTagline;

  /// No description provided for @todayCheckInTitle.
  ///
  /// In en, this message translates to:
  /// **'Today\'s Check-in'**
  String get todayCheckInTitle;

  /// No description provided for @todayCheckInSubtitle.
  ///
  /// In en, this message translates to:
  /// **'A minute to log how you feel.'**
  String get todayCheckInSubtitle;

  /// No description provided for @todayMicroReflection.
  ///
  /// In en, this message translates to:
  /// **'A reflection'**
  String get todayMicroReflection;

  /// No description provided for @todayMicroInvitation.
  ///
  /// In en, this message translates to:
  /// **'Today\'s invitation'**
  String get todayMicroInvitation;

  /// No description provided for @todayActivePlanLabel.
  ///
  /// In en, this message translates to:
  /// **'Today\'s plan'**
  String get todayActivePlanLabel;

  /// No description provided for @todayActivePlanEmpty.
  ///
  /// In en, this message translates to:
  /// **'No plan for today.'**
  String get todayActivePlanEmpty;

  /// No description provided for @myStoryWeekProgress.
  ///
  /// In en, this message translates to:
  /// **'Week {current} of {total}'**
  String myStoryWeekProgress(Object current, Object total);

  /// No description provided for @myStoryWeekTitle.
  ///
  /// In en, this message translates to:
  /// **'Week {n}'**
  String myStoryWeekTitle(Object n);

  /// No description provided for @myStorySessionNotStarted.
  ///
  /// In en, this message translates to:
  /// **'This week\'s session hasn\'t started'**
  String get myStorySessionNotStarted;

  /// No description provided for @myStorySessionInProgress.
  ///
  /// In en, this message translates to:
  /// **'Continue last session'**
  String get myStorySessionInProgress;

  /// No description provided for @myStorySessionCompleted.
  ///
  /// In en, this message translates to:
  /// **'Done this week'**
  String get myStorySessionCompleted;

  /// No description provided for @myStoryStartCta.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get myStoryStartCta;

  /// No description provided for @myStoryContinueCta.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get myStoryContinueCta;

  /// No description provided for @myStoryRereadCta.
  ///
  /// In en, this message translates to:
  /// **'Re-read'**
  String get myStoryRereadCta;

  /// No description provided for @myStoryTimelineHeader.
  ///
  /// In en, this message translates to:
  /// **'Your story so far'**
  String get myStoryTimelineHeader;

  /// No description provided for @myStoryHistoryHeader.
  ///
  /// In en, this message translates to:
  /// **'Past sessions'**
  String get myStoryHistoryHeader;

  /// No description provided for @myStoryHistoryEmpty.
  ///
  /// In en, this message translates to:
  /// **'No completed sessions yet.'**
  String get myStoryHistoryEmpty;

  /// No description provided for @meItemProgress.
  ///
  /// In en, this message translates to:
  /// **'Your week'**
  String get meItemProgress;

  /// No description provided for @meItemActionLoop.
  ///
  /// In en, this message translates to:
  /// **'Follow-up plans'**
  String get meItemActionLoop;

  /// No description provided for @meItemArticles.
  ///
  /// In en, this message translates to:
  /// **'Read a little'**
  String get meItemArticles;

  /// No description provided for @meItemCrisis.
  ///
  /// In en, this message translates to:
  /// **'Crisis support'**
  String get meItemCrisis;

  /// No description provided for @meItemProfile.
  ///
  /// In en, this message translates to:
  /// **'My profile'**
  String get meItemProfile;

  /// No description provided for @meItemProgressSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Mood and social moments across the week'**
  String get meItemProgressSubtitle;

  /// No description provided for @meItemActionLoopSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Track the small steps you set'**
  String get meItemActionLoopSubtitle;

  /// No description provided for @meItemArticlesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Short reads on loneliness and well-being'**
  String get meItemArticlesSubtitle;

  /// No description provided for @meItemCrisisSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Who to reach in an emergency'**
  String get meItemCrisisSubtitle;

  /// No description provided for @meItemProfileSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Update your details'**
  String get meItemProfileSubtitle;

  /// No description provided for @safetyPillLow.
  ///
  /// In en, this message translates to:
  /// **'Talk now'**
  String get safetyPillLow;

  /// No description provided for @safetyPillModerate.
  ///
  /// In en, this message translates to:
  /// **'Need support?'**
  String get safetyPillModerate;

  /// No description provided for @safetyPillAcute.
  ///
  /// In en, this message translates to:
  /// **'Crisis line'**
  String get safetyPillAcute;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when language+script+country codes are specified.
  switch (locale.toString()) {
    case 'zh_Hant_HK':
      return AppLocalizationsZhHantHk();
  }

  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
