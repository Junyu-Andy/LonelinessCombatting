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
      'This demo presents the product through four core modules: trust building, context understanding, action support, and steady follow-up.';

  @override
  String get contextSubtitle =>
      'Quick check-ins, social map, and recent interaction reflection will live here.';

  @override
  String get actionSubtitle =>
      'Tailored prompts, conversation starters, and activity suggestions will live here.';

  @override
  String get followUpSubtitle =>
      'Reminders, progress review, and adaptive pacing will live here.';

  @override
  String get settingsSubtitle =>
      'Language, system boundaries, and about this demo will live here.';

  @override
  String get onboardingWelcomeTitle => 'A calmer way to begin';

  @override
  String get onboardingWelcomeBody =>
      'This demo shows the overall structure of the app and how each core module connects together.';

  @override
  String get onboardingHelpTitle => 'What this app can help with';

  @override
  String get onboardingHelpBody =>
      'It can guide check-ins, surface social context, suggest small next steps, and support steady follow-up.';

  @override
  String get onboardingBoundaryTitle => 'System boundaries';

  @override
  String get onboardingBoundaryBody =>
      'This demo gives structure and suggestions. It does not replace emergency help, diagnosis, or professional care.';

  @override
  String get onboardingBoundaryItemOne =>
      'It can help you reflect and prepare.';

  @override
  String get onboardingBoundaryItemTwo =>
      'It can suggest small, concrete actions.';

  @override
  String get onboardingBoundaryItemThree =>
      'It should not be treated as crisis support.';

  @override
  String get onboardingStartTitle => 'Ready to enter the demo';

  @override
  String get onboardingStartBody =>
      'You can start with the main structure first. Detailed content for each module will be added step by step.';

  @override
  String get back => 'Back';

  @override
  String get next => 'Next';

  @override
  String get enterDemo => 'Enter Demo';
}
