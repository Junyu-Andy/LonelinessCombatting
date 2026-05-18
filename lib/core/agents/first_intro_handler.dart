/// First-turn self-introduction logic (Dev Req §3.3).
///
/// Each agent introduces itself exactly once per user. The decision is
/// driven by `UserProfile.firstIntroSeen` — a Map keyed by agent id, with
/// the timestamp of the first showing as value. Missing keys mean the
/// intro has not been played yet.
///
/// The handler is pure-logic: deciding *whether* to show is separate
/// from rendering. UI surfaces (M2 page, M3 page, Tung Tung page) call
/// [shouldShowFor] when they mount and call [markShown] once the intro
/// has been displayed and dismissed.
library;

import '../../features/auth/data/auth_service.dart';
import '../../features/auth/data/user_profile.dart';
import 'agent_registry.dart';

class FirstIntroHandler {
  FirstIntroHandler({required this.authService});

  final AuthService authService;

  /// Whether [agent] has not yet introduced itself to the profile in
  /// [profile]. Returns false for null profiles (guest mode — no intro
  /// is shown because there's no persistent identity to record it
  /// against).
  bool shouldShowFor({
    required UserProfile? profile,
    required AgentDefinition agent,
  }) {
    if (profile == null) return false;
    return !profile.firstIntroSeen.containsKey(agent.id);
  }

  /// Persist the fact that [agent] has now introduced itself. Returns
  /// the updated profile so the caller can push it through
  /// `AppSettings.profile` immediately (no need to wait for the
  /// Firestore round-trip to complete before re-rendering).
  Future<UserProfile> markShown({
    required UserProfile profile,
    required AgentDefinition agent,
    DateTime? at,
  }) async {
    final when = at ?? DateTime.now();
    final next = Map<String, DateTime>.from(profile.firstIntroSeen);
    next[agent.id] = when;
    final updated = profile.copyWith(firstIntroSeen: next);
    try {
      await authService.updateProfile(updated);
    } on AuthUnavailableException {
      // Guest mode — keep state in memory only. The intro will replay
      // next session, which is fine (the intro is light).
    }
    return updated;
  }

  /// Resolve the localised intro text for [agent]. Returns the
  /// language-appropriate string, defaulting to Cantonese (`zh`) when
  /// the locale isn't English.
  String introTextFor({
    required AgentDefinition agent,
    required String localeCode,
  }) {
    final intro = AgentRegistry.introTextFor(agent.introTextKey);
    if (intro == null) return '';
    return localeCode == 'en' ? intro.en : intro.zh;
  }
}
