// T46 (C16) — the S9 close button's first-use note is shown once per phone:
// the "already explained" marker is kept on the device (shared_preferences)
// and comes back when the App is reopened.  Same in both arms; the wording
// (still a 【占位】 draft) is unchanged.
import 'package:app_demo/features/brief_pr/presentation/widgets/session_close_button.dart';
import 'package:app_demo/features/brief_pr/presentation/widgets/session_close_hint.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SessionCloseHint.resetForTest();
  });

  Widget page({VoidCallback? onPressed}) => MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            leading: SessionCloseButton(onPressed: onPressed ?? () {}),
            leadingWidth: SessionCloseButton.leadingWidth,
            title: const Text('通通'),
          ),
        ),
      );

  group('SessionCloseHint marker', () {
    test('nothing stored: not yet shown; first claim wins, then stored',
        () async {
      await SessionCloseHint.restore();
      expect(SessionCloseHint.alreadyShown, isFalse);
      expect(SessionCloseHint.claimFirstUse(), isTrue);
      expect(SessionCloseHint.claimFirstUse(), isFalse);
      await pumpEventQueue(); // the write is fire-and-forget
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(SessionCloseHint.key), isTrue);
    });

    test('marker stored (= App reopened on the same phone): never shown again',
        () async {
      SharedPreferences.setMockInitialValues({SessionCloseHint.key: true});
      await SessionCloseHint.restore();
      expect(SessionCloseHint.alreadyShown, isTrue);
      expect(SessionCloseHint.claimFirstUse(), isFalse);
    });

    test('shown, then rebuilt from storage: still shown', () async {
      await SessionCloseHint.restore();
      expect(SessionCloseHint.claimFirstUse(), isTrue);
      await pumpEventQueue();
      SessionCloseHint.resetForTest(); // forget the in-memory flag only
      await SessionCloseHint.restore();
      expect(SessionCloseHint.alreadyShown, isTrue);
      expect(SessionCloseHint.claimFirstUse(), isFalse);
    });

    test('a bad stored value counts as not shown', () async {
      SharedPreferences.setMockInitialValues({SessionCloseHint.key: 'yes'});
      await SessionCloseHint.restore();
      expect(SessionCloseHint.alreadyShown, isFalse);
    });

    test('no store (restore not run): T25 once-per-process behaviour',
        () async {
      SessionCloseHint.resetForTest(store: null);
      expect(SessionCloseHint.claimFirstUse(), isTrue);
      expect(SessionCloseHint.claimFirstUse(), isFalse);
      // Nothing was written anywhere.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(SessionCloseHint.key), isNull);
    });
  });

  group('S9 close button with the marker', () {
    testWidgets('first page on a new phone shows the note and stores the marker',
        (tester) async {
      await SessionCloseHint.restore();
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();
      expect(find.text(SessionCloseButton.label), findsOneWidget);
      expect(find.text(SessionCloseButton.firstUseNote), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(SessionCloseHint.key), isTrue);
    });

    testWidgets('App reopened (marker stored): button yes, note no',
        (tester) async {
      SharedPreferences.setMockInitialValues({SessionCloseHint.key: true});
      await SessionCloseHint.restore();
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();
      expect(find.text(SessionCloseButton.label), findsOneWidget);
      expect(find.text(SessionCloseButton.firstUseNote), findsNothing);
    });

    testWidgets('wording final (1014e §2.8 keeps the T25 draft text)', (tester) async {
      expect(SessionCloseButton.label, '今日傾到呢度');
      expect(SessionCloseButton.firstUseNote,
          '撳「今日傾到呢度」就係今次傾完；想再傾隨時返嚟。');
    });
  });
}
