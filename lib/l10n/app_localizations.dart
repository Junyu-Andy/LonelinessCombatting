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
  /// **'AppName'**
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
  /// **'Settings'**
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
  String get tabToday;

  /// No description provided for @tabMyStory.
  String get tabMyStory;

  /// No description provided for @tabMe.
  String get tabMe;

  String get greetingMorning;
  String get greetingAfternoon;
  String get greetingEvening;
  String get greetingNight;
  // Item 3 (Research v2): tagline extracted to l10n for trademark-safe swapping.
  // ⚠️ HIGH collision risk with gov "陪我講 Shall We Talk" — keep pending legal sign-off.
  String get greetingTagline;

  String get todayCheckInTitle;
  String get todayCheckInSubtitle;
  String get todayMicroReflection;
  String get todayMicroInvitation;
  String get todayActivePlanLabel;
  String get todayActivePlanEmpty;

  String myStoryWeekProgress(int current, int total);
  String myStoryWeekTitle(int n);
  String get myStorySessionNotStarted;
  String get myStorySessionInProgress;
  String get myStorySessionCompleted;
  String get myStoryStartCta;
  String get myStoryContinueCta;
  String get myStoryRereadCta;
  String get myStoryTimelineHeader;
  String get myStoryHistoryHeader;
  String get myStoryHistoryEmpty;

  String get meItemProgress;
  String get meItemActionLoop;
  String get meItemArticles;
  String get meItemCrisis;
  String get meItemProfile;
  String get meItemProgressSubtitle;
  String get meItemActionLoopSubtitle;
  String get meItemArticlesSubtitle;
  String get meItemCrisisSubtitle;
  String get meItemProfileSubtitle;

  String get safetyPillLow;
  String get safetyPillModerate;
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
