/// T47 rev. 10/16 — part B of the intake, the only intake screen the elder
/// sees while the researcher records the rest (`researcherIntakeEnabled`
/// on; dev-tasks-1015-intake rev. 10/16 §1 B, §2.2): 重要嘅人 and
/// 想重新聯絡嘅人, typed by the elder (the researcher helps, never types for
/// them).  At most 10 rows per list (dev-tasks-1018 §A2): at 10 the add
/// button goes away.  Wording is the retired six-part page's Part 2 (minus
/// the old caps), see docs/spec/copy S19.
///
/// Writes `users/{uid}/onboarding/intake` (importantPeople, reconnectPeople,
/// completedParts += 2; merge, so the researcher's part A stays) and the
/// profile's closeContacts and reconnectContacts (share: true — the elder
/// typed them for the companions, T48 / T49a; the action plan's quick
/// picks read both) + intakePeopleDone.  Names go through the shared safety
/// check (T7).  The Hybrid-arm memory facts for these people are written by
/// the server when the researcher records (from the merged document); if
/// the elder fills this page after that, the researcher records once more.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../app/app_settings_scope.dart';
import '../../../../core/safety/safety_check.dart';
import '../../../auth/data/user_profile.dart';
import '../../../auth/presentation/auth_service_scope.dart';
import '../../data/intake_repository.dart';
import '../../data/intake_response.dart';

/// S19 — the elder-facing wording (retired Part 2, caps removed).
class IntakePeopleCopy {
  IntakePeopleCopy._();
  static const title = '生命中重要嘅人';
  static const intro = '你最重視嘅人係邊幾個？（可以跳過）';
  static const reconnectTitle = '想重新聯絡嘅人';
  static const reconnectIntro = '有冇人你希望可以重拾聯絡？（可以跳過）';
  static const nameLabel = '姓名 / 稱呼';
  static const relationLabel = '關係（例如：女兒、舊朋友）';
  static const addImportant = '+ 加一位重要嘅人';
  static const addReconnect = '+ 加一位想聯絡嘅人';
  static const done = '完成';
  static const initialRows = 3;

  /// dev-tasks-1018 §A2: each list at most 10 people (the server checks the
  /// same, functions/researcher_intake.js MAX_PEOPLE).
  static const maxRows = 10;
}

class IntakePeoplePage extends StatefulWidget {
  final VoidCallback onComplete;

  /// Injectable for tests (defaults to Firestore).
  final IntakeRepository? repository;

  const IntakePeoplePage(
      {super.key, required this.onComplete, this.repository});

  @override
  State<IntakePeoplePage> createState() => _IntakePeoplePageState();
}

typedef _Row = ({TextEditingController name, TextEditingController rel});

class _IntakePeoplePageState extends State<IntakePeoplePage> {
  late final IntakeRepository _repo = widget.repository ?? IntakeRepository();
  final List<_Row> _important = [
    for (var i = 0; i < IntakePeopleCopy.initialRows; i++) _newRow(),
  ];
  final List<_Row> _reconnect = [_newRow()];
  bool _saving = false;

  static _Row _newRow() =>
      (name: TextEditingController(), rel: TextEditingController());

  @override
  void dispose() {
    for (final r in [..._important, ..._reconnect]) {
      r.name.dispose();
      r.rel.dispose();
    }
    super.dispose();
  }

  List<PersonEntry> _entries(List<_Row> rows) => [
        for (final r in rows)
          if (r.name.text.trim().isNotEmpty)
            PersonEntry(
                name: r.name.text.trim(), relationship: r.rel.text.trim()),
      ];

  static List<CloseContact> _contacts(List<PersonEntry> people) => [
        for (final p in people)
          CloseContact(
              name: p.name,
              relation: p.relationship.isEmpty ? null : p.relationship,
              share: true),
      ];

  Future<void> _complete() async {
    setState(() => _saving = true);
    final profile = AppSettingsScope.read(context).profile;
    if (profile != null) {
      final important = _entries(_important);
      final reconnect = _entries(_reconnect);
      final auth = AuthServiceScope.of(context);
      final settings = AppSettingsScope.read(context);
      final updated = profile.copyWith(
        intakePeopleDone: true,
        closeContacts: _contacts(important),
        reconnectContacts: _contacts(reconnect),
      );
      // In-memory first so the gate moves on at once; the Firestore writes
      // go fire-and-forget (the SDK queues them offline).
      settings.profile = updated;
      unawaited(() async {
        try {
          await _repo.savePeople(profile.uid,
              important: important, reconnect: reconnect);
        } catch (_) {}
      }());
      unawaited(() async {
        try {
          await auth.updateProfile(updated);
        } catch (_) {}
      }());
      // T7 — names and relations go through the shared safety check (both
      // arms; the arm is not known yet).
      final safety = SafetyService.of(context);
      final text = [
        for (final p in [...important, ...reconnect]) ...[
          p.name,
          p.relationship
        ],
      ].where((x) => x.isNotEmpty).join('\n');
      final List<SafetyCheckResult> results;
      if (safety.classifierActiveFor(SafetyInputPoint.intakeOtherText)) {
        results = [
          await safety.checkUserTextClassified(text,
              point: SafetyInputPoint.intakeOtherText, uid: profile.uid),
        ];
        if (!mounted) return;
      } else {
        results = [
          safety.checkUserText(text,
              point: SafetyInputPoint.intakeOtherText, uid: profile.uid),
        ];
      }
      await safety.route(context, results);
      if (!mounted) return;
    }
    setState(() => _saving = false);
    widget.onComplete();
  }

  List<Widget> _rows(String keyPrefix, List<_Row> rows) => [
        for (var i = 0; i < rows.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(children: [
              Expanded(
                child: TextField(
                  key: Key('${keyPrefix}_name_$i'),
                  controller: rows[i].name,
                  scrollPadding: const EdgeInsets.only(bottom: 160),
                  decoration: const InputDecoration(
                      labelText: IntakePeopleCopy.nameLabel),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  key: Key('${keyPrefix}_rel_$i'),
                  controller: rows[i].rel,
                  scrollPadding: const EdgeInsets.only(bottom: 160),
                  decoration: const InputDecoration(
                      labelText: IntakePeopleCopy.relationLabel),
                ),
              ),
            ]),
          ),
      ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget heading(String title, String intro) => Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(intro,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
          ),
        );
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                children: [
                  heading(IntakePeopleCopy.title, IntakePeopleCopy.intro),
                  ..._rows('intake_people_important', _important),
                  if (_important.length < IntakePeopleCopy.maxRows)
                    OutlinedButton.icon(
                      key: const Key('intake_people_add_important'),
                      onPressed: () =>
                          setState(() => _important.add(_newRow())),
                      icon: const Icon(Icons.person_add_alt),
                      style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 52)),
                      label: const Text(IntakePeopleCopy.addImportant),
                    ),
                  const SizedBox(height: 32),
                  heading(IntakePeopleCopy.reconnectTitle,
                      IntakePeopleCopy.reconnectIntro),
                  ..._rows('intake_people_reconnect', _reconnect),
                  if (_reconnect.length < IntakePeopleCopy.maxRows)
                    OutlinedButton.icon(
                      key: const Key('intake_people_add_reconnect'),
                      onPressed: () =>
                          setState(() => _reconnect.add(_newRow())),
                      icon: const Icon(Icons.person_add_alt),
                      style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 52)),
                      label: const Text(IntakePeopleCopy.addReconnect),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: FilledButton(
                key: const Key('intake_people_done'),
                onPressed: _saving ? null : _complete,
                style: FilledButton.styleFrom(minimumSize: const Size(0, 56)),
                child: const Text(IntakePeopleCopy.done),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
