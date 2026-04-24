// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Companion Demo';

  @override
  String get homeTab => 'Home';

  @override
  String get contextTab => 'Context';

  @override
  String get actionTab => 'Support';

  @override
  String get followUpTab => 'Follow-up';

  @override
  String get settingsTab => 'Settings';

  @override
  String get homeSubtitle => 'This is the home overview for the demo.';

  @override
  String get homeStructureHint =>
      'Four modules: Trust → Context → Action → Follow-up.';

  @override
  String get contextSubtitle => 'Check-ins, social map, recent moments.';

  @override
  String get actionSubtitle => 'Prompts, openers, activities.';

  @override
  String get followUpSubtitle => 'Reminders, progress, pacing.';

  @override
  String get settingsSubtitle => 'Language, boundaries, about.';

  @override
  String get onboardingWelcomeTitle => 'A calmer start';

  @override
  String get onboardingWelcomeBody => "A quick look at the app's structure.";

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
}
