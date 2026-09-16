/// V-1 — runtime-readable version pin (Phase A baseline).
///
/// [BuildInfo] is a thin façade over the generated constants in
/// `build_info.g.dart`, which `tool/export_spec_inputs.py` regenerates from
/// `pubspec.yaml`, the lexicon source, the three prompt files, the context
/// suffix template and the two safety JSONs.  Never edit the `.g.dart` by
/// hand: `test/phase_a_version_pin_test.dart` recomputes the bundle hash
/// from the repo files and fails if the generated value is stale.
library;

import 'build_info.g.dart';

class BuildInfo {
  BuildInfo._();

  static String get appVersion => kAppVersion;
  static String get buildNumber => kBuildNumber;
  static String get lexiconVersion => kLexiconVersion;

  /// SHA-256 over the three prompts + context-suffix template +
  /// safety_acknowledgements.json + crisis_resources.json +
  /// llm_fallback_messages.json (see the tool for the exact recipe).
  static String get promptBundleHash => kPromptBundleHash;
  static String get promptBundleHashShort =>
      kPromptBundleHash.length >= 8 ? kPromptBundleHash.substring(0, 8) : kPromptBundleHash;
  static String get generatedAt => kGeneratedAt;
  static Map<String, String> get artefactHashes => kArtefactHashes;
}
