// 10/14 (lead's decision, before the first participant): in a PHASE_B
// build the Hybrid-only 👍/👎 reply feedback and the Phase A first-week
// nudge are hidden in both arms unless the matching remote flag is true.
// Run with and without --dart-define=PHASE_B=true (tool/ci_flutter_tests.sh
// does both).
import 'package:app_demo/core/feature_flags/feature_flags.dart';
import 'package:app_demo/core/feature_flags/remote_feature_flags.dart';
import 'package:app_demo/features/response_feedback/presentation/widgets/thumbs_feedback.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => RemoteFeatureFlags.current = const RemoteFeatureFlags());
  tearDown(() => RemoteFeatureFlags.current = const RemoteFeatureFlags());

  test('flags parse: only literal true turns them on', () {
    expect(RemoteFeatureFlags.fromMap(const {}).replyFeedbackEnabled, false);
    expect(RemoteFeatureFlags.fromMap(const {}).week1NudgeEnabled, false);
    expect(
        RemoteFeatureFlags.fromMap(const {'replyFeedbackEnabled': 'true'})
            .replyFeedbackEnabled,
        false);
    expect(
        RemoteFeatureFlags.fromMap(const {'replyFeedbackEnabled': true})
            .replyFeedbackEnabled,
        true);
    expect(
        RemoteFeatureFlags.fromMap(const {'week1NudgeEnabled': true})
            .week1NudgeEnabled,
        true);
  });

  test('hide getters follow the build and the flags', () {
    expect(RemoteFeatureFlags.hideReplyFeedback, FeatureFlags.phaseB);
    expect(RemoteFeatureFlags.hideWeek1Nudge, FeatureFlags.phaseB);
    RemoteFeatureFlags.current =
        const RemoteFeatureFlags(replyFeedbackEnabled: true, week1NudgeEnabled: true);
    expect(RemoteFeatureFlags.hideReplyFeedback, false);
    expect(RemoteFeatureFlags.hideWeek1Nudge, false);
  });

  testWidgets('ThumbsFeedback renders nothing in a Phase B build by default',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: ThumbsFeedback(agentId: 'siu_yan', moduleId: 'm2_check_in'),
      ),
    ));
    final thumbs = find.byIcon(Icons.thumb_up_alt_outlined);
    if (FeatureFlags.phaseB) {
      expect(thumbs, findsNothing, reason: 'Phase B hides reply feedback');
    } else {
      expect(thumbs, findsOneWidget, reason: 'Phase A build unchanged');
    }
  });

  testWidgets('ThumbsFeedback comes back when replyFeedbackEnabled is true',
      (tester) async {
    RemoteFeatureFlags.current =
        const RemoteFeatureFlags(replyFeedbackEnabled: true);
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: ThumbsFeedback(agentId: 'tung_tung', moduleId: 'tung_tung_chat'),
      ),
    ));
    expect(find.byIcon(Icons.thumb_up_alt_outlined), findsOneWidget);
    expect(find.byIcon(Icons.thumb_down_alt_outlined), findsOneWidget);
  });
}
