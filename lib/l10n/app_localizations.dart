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
  /// **'Companion Demo'**
  String get appTitle;

  /// No description provided for @homeTab.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get homeTab;

  /// No description provided for @contextTab.
  ///
  /// In en, this message translates to:
  /// **'Context'**
  String get contextTab;

  /// No description provided for @actionTab.
  ///
  /// In en, this message translates to:
  /// **'Support'**
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

  /// No description provided for @chatTab.
  String get chatTab;

  /// No description provided for @chatSubtitle.
  String get chatSubtitle;

  /// No description provided for @developerCredit.
  String get developerCredit;

  /// No description provided for @developerCreditShort.
  String get developerCreditShort;

  /// No description provided for @homeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'This is the home overview for the demo.'**
  String get homeSubtitle;

  /// No description provided for @homeStructureHint.
  ///
  /// In en, this message translates to:
  /// **'This demo presents the product through four core modules: trust building, context understanding, action support, and steady follow-up.'**
  String get homeStructureHint;

  /// No description provided for @contextSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Quick check-ins, social map, and recent interaction reflection will live here.'**
  String get contextSubtitle;

  /// No description provided for @actionSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Tailored prompts, conversation starters, and activity suggestions will live here.'**
  String get actionSubtitle;

  /// No description provided for @followUpSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Reminders, progress review, and adaptive pacing will live here.'**
  String get followUpSubtitle;

  /// No description provided for @settingsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Language, system boundaries, and about this demo will live here.'**
  String get settingsSubtitle;

  /// No description provided for @onboardingWelcomeTitle.
  ///
  /// In en, this message translates to:
  /// **'A calmer way to begin'**
  String get onboardingWelcomeTitle;

  /// No description provided for @onboardingWelcomeBody.
  ///
  /// In en, this message translates to:
  /// **'This demo shows the overall structure of the app and how each core module connects together.'**
  String get onboardingWelcomeBody;

  /// No description provided for @onboardingHelpTitle.
  ///
  /// In en, this message translates to:
  /// **'What this app can help with'**
  String get onboardingHelpTitle;

  /// No description provided for @onboardingHelpBody.
  ///
  /// In en, this message translates to:
  /// **'It can guide check-ins, surface social context, suggest small next steps, and support steady follow-up.'**
  String get onboardingHelpBody;

  /// No description provided for @onboardingBoundaryTitle.
  ///
  /// In en, this message translates to:
  /// **'System boundaries'**
  String get onboardingBoundaryTitle;

  /// No description provided for @onboardingBoundaryBody.
  ///
  /// In en, this message translates to:
  /// **'This demo gives structure and suggestions. It does not replace emergency help, diagnosis, or professional care.'**
  String get onboardingBoundaryBody;

  /// No description provided for @onboardingBoundaryItemOne.
  ///
  /// In en, this message translates to:
  /// **'It can help you reflect and prepare.'**
  String get onboardingBoundaryItemOne;

  /// No description provided for @onboardingBoundaryItemTwo.
  ///
  /// In en, this message translates to:
  /// **'It can suggest small, concrete actions.'**
  String get onboardingBoundaryItemTwo;

  /// No description provided for @onboardingBoundaryItemThree.
  ///
  /// In en, this message translates to:
  /// **'It should not be treated as crisis support.'**
  String get onboardingBoundaryItemThree;

  /// No description provided for @onboardingStartTitle.
  ///
  /// In en, this message translates to:
  /// **'Ready to enter the demo'**
  String get onboardingStartTitle;

  /// No description provided for @onboardingStartBody.
  ///
  /// In en, this message translates to:
  /// **'You can start with the main structure first. Detailed content for each module will be added step by step.'**
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
