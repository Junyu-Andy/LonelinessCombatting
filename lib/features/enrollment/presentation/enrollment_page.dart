/// T19 (decision 0029) — 研究員登記 page for the unblinded researcher.
///
/// Flow: fill in the participant's login email, research ID, W0 paper DJG
/// emotional score (0–3), Ah Jan / Ah Bak pairing and W0 date → 「檢查」
/// (server dry run: finds the account, shows its display name; never the
/// arm) → confirmation dialog that asks for the score a second time →
/// 「確認登記」 → the server allocates and the arm is shown here, for the
/// briefing.  Only accounts with the `unblinded` claim reach this page
/// (StaffGate); the server checks the claim again.
///
/// Staff-facing text, not participant-facing.
library;

import 'package:flutter/material.dart';

import '../data/enrollment_service.dart';

class EnrollmentPage extends StatefulWidget {
  final EnrollmentBackend backend;

  /// Today's date (Hong Kong), injectable for tests.
  final DateTime Function() today;

  final VoidCallback? onSignOut;

  const EnrollmentPage({
    super.key,
    this.backend = const CloudEnrollmentBackend(),
    this.today = DateTime.now,
    this.onSignOut,
  });

  @override
  State<EnrollmentPage> createState() => _EnrollmentPageState();
}

String _dateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}'
    '-${d.day.toString().padLeft(2, '0')}';

String armLabel(String? arm) => switch (arm) {
      'A' => 'A 組（Hybrid：規則 + AI）',
      'B' => 'B 組（規則組）',
      _ => '—',
    };

String stratumLabel(String stratum) =>
    stratum == 'low' ? '低層（0–1 分）' : '高層（2–3 分）';

String variantLabel(String? v) => v == 'masculine' ? '阿伯' : '阿珍';

/// Server error code → what the researcher should do.
String enrollmentErrorText(String code) => switch (code) {
      'disabled' => '登記功能未開（meta/randomization_config）。請聯絡負責人。',
      'not_unblinded_researcher' => '呢個帳號冇非盲研究員權限。',
      'account_not_found' => '搵唔到呢個電郵嘅老人家帳號。請檢查電郵，或者先幫老人家註冊。',
      'invalid_research_id' => '研究編號格式唔啱（2–12 個英文字母、數字或 -）。',
      'invalid_score' => '情感分要係 0、1、2 或 3。',
      'invalid_variant' => '請揀阿珍或者阿伯。',
      'invalid_w0_date' => 'W0 日期唔啱（唔可以係將來）。',
      'research_id_taken' => '呢個研究編號已經登記咗第二個帳號。',
      'account_has_other_research_id' => '呢個帳號已經有另一個研究編號。',
      'already_has_arm' => '呢個帳號已經有組別（試用或 Phase A 帳號），唔可以再分組。',
      'tester_account' => '測試員帳號唔可以登記。',
      'own_account' => '唔可以登記自己個研究員帳號。',
      'sequence_missing' => '分配序列未上載。請先執行 tool/randomization_sequence.js。',
      'sequence_exhausted' => '呢一層嘅分配序列用晒。請即刻聯絡負責人。',
      _ => '登記失敗（$code）。請再試，或者聯絡負責人。',
    };

class _EnrollmentPageState extends State<EnrollmentPage> {
  final _email = TextEditingController();
  final _researchId = TextEditingController();
  int? _score;
  String? _variant;
  late DateTime _w0;
  bool _busy = false;
  String? _error;
  EnrollmentResult? _result;

  @override
  void initState() {
    super.initState();
    _w0 = widget.today();
  }

  @override
  void dispose() {
    _email.dispose();
    _researchId.dispose();
    super.dispose();
  }

  bool get _complete =>
      _email.text.trim().isNotEmpty &&
      _researchId.text.trim().isNotEmpty &&
      _score != null &&
      _variant != null;

  EnrollmentInput _input() => EnrollmentInput(
        email: _email.text,
        researchId: _researchId.text,
        w0DjgEmotional: _score!,
        companionVariant: _variant!,
        w0Date: _dateKey(_w0),
      );

  Future<void> _check() async {
    final input = _input();
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    try {
      final preview = await widget.backend.submit(input, dryRun: true);
      if (!mounted) return;
      setState(() => _busy = false);
      if (preview.alreadyEnrolled) {
        // Already registered: no new allocation; show the stored one.
        final stored = await widget.backend.submit(input, dryRun: false);
        if (mounted) setState(() => _result = stored);
        return;
      }
      final ok = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _ConfirmDialog(input: input, preview: preview),
      );
      if (ok != true || !mounted) return;
      setState(() => _busy = true);
      final result = await widget.backend.submit(input, dryRun: false);
      if (mounted) setState(() => _result = result);
    } on EnrollmentError catch (e) {
      if (mounted) setState(() => _error = enrollmentErrorText(e.code));
    } catch (e) {
      if (mounted) setState(() => _error = enrollmentErrorText('$e'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _reset() {
    setState(() {
      _email.clear();
      _researchId.clear();
      _score = null;
      _variant = null;
      _w0 = widget.today();
      _result = null;
      _error = null;
    });
  }

  Future<void> _pickDate() async {
    final today = widget.today();
    final picked = await showDatePicker(
      context: context,
      initialDate: _w0,
      firstDate: today.subtract(const Duration(days: 60)),
      lastDate: today,
    );
    if (picked != null) setState(() => _w0 = picked);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('研究員登記'),
        actions: [
          if (widget.onSignOut != null)
            TextButton(onPressed: widget.onSignOut, child: const Text('登出')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (_result != null)
            _ResultCard(result: _result!, onNext: _reset)
          else ...[
            Text('先幫老人家喺佢部手機註冊，再喺度登記。',
                style: theme.textTheme.bodyMedium),
            const SizedBox(height: 16),
            TextField(
              key: const Key('enroll_email'),
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                  labelText: '老人家登入電郵', border: OutlineInputBorder()),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('enroll_research_id'),
              controller: _researchId,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                  labelText: '研究編號', border: OutlineInputBorder()),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            Text('W0 紙本 DJG 情感分量表分（第 1–3 題）',
                style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            _ScoreChips(
              keyPrefix: 'enroll_score',
              selected: _score,
              onSelected: (v) => setState(() => _score = v),
            ),
            const SizedBox(height: 16),
            Text('配對', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              for (final v in const ['feminine', 'masculine'])
                ChoiceChip(
                  key: Key('enroll_variant_$v'),
                  label: Text(variantLabel(v)),
                  selected: _variant == v,
                  onSelected: (_) => setState(() => _variant = v),
                ),
            ]),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('W0 入組日期'),
              subtitle: Text(_dateKey(_w0)),
              trailing: const Icon(Icons.edit_calendar_outlined),
              onTap: _busy ? null : _pickDate,
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!,
                  key: const Key('enroll_error'),
                  style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 20),
            FilledButton(
              key: const Key('enroll_check'),
              onPressed: _complete && !_busy ? _check : null,
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('檢查'),
            ),
          ],
        ],
      ),
    );
  }
}

class _ScoreChips extends StatelessWidget {
  final String keyPrefix;
  final int? selected;
  final ValueChanged<int> onSelected;
  const _ScoreChips(
      {required this.keyPrefix,
      required this.selected,
      required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return Wrap(spacing: 8, children: [
      for (var v = 0; v <= 3; v++)
        ChoiceChip(
          key: Key('${keyPrefix}_$v'),
          label: Text('$v 分'),
          selected: selected == v,
          onSelected: (_) => onSelected(v),
        ),
    ]);
  }
}

/// Shows everything once more and asks for the score a second time; the
/// button stays off until the two scores match.
class _ConfirmDialog extends StatefulWidget {
  final EnrollmentInput input;
  final EnrollmentResult preview;
  const _ConfirmDialog({required this.input, required this.preview});

  @override
  State<_ConfirmDialog> createState() => _ConfirmDialogState();
}

class _ConfirmDialogState extends State<_ConfirmDialog> {
  int? _again;

  @override
  Widget build(BuildContext context) {
    final i = widget.input;
    final p = widget.preview;
    final created = p.accountCreatedAt == null
        ? '—'
        : p.accountCreatedAt!.substring(0, 10);
    final matches = _again == i.w0DjgEmotional;
    return AlertDialog(
      title: const Text('確認登記'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('帳號：${p.displayName ?? '—'}（${i.email.trim()}，$created 註冊）'),
            Text('研究編號：${p.researchId}'),
            Text('情感分：${i.w0DjgEmotional} 分 → ${stratumLabel(i.stratum)}'),
            Text('配對：${variantLabel(i.companionVariant)}'),
            Text('W0 日期：${i.w0Date}'),
            const SizedBox(height: 12),
            const Text('請再揀一次情感分：'),
            const SizedBox(height: 8),
            _ScoreChips(
              keyPrefix: 'enroll_score_again',
              selected: _again,
              onSelected: (v) => setState(() => _again = v),
            ),
            if (_again != null && !matches)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('兩次情感分唔一樣，請核對紙本。',
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            const SizedBox(height: 8),
            const Text('登記後唔可以改。'),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('返回修改'),
        ),
        FilledButton(
          key: const Key('enroll_confirm'),
          onPressed: matches ? () => Navigator.of(context).pop(true) : null,
          child: const Text('確認登記'),
        ),
      ],
    );
  }
}

class _ResultCard extends StatelessWidget {
  final EnrollmentResult result;
  final VoidCallback onNext;
  const _ResultCard({required this.result, required this.onNext});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(result.alreadyEnrolled ? '已經登記過，組別不變' : '登記完成',
                style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            Text('研究編號：${result.researchId}'),
            Text('分層：${stratumLabel(result.stratum)}'),
            Text('組別：${armLabel(result.arm)}',
                key: const Key('enroll_arm'),
                style: theme.textTheme.titleMedium),
            if (result.alreadyEnrolled && !result.sameInput)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '今次輸入同第一次登記唔一樣，記錄以第一次為準。'
                  '如果要更正，要按程序用管理腳本並寫明理由。',
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            const SizedBox(height: 12),
            const Text('請老人家完全關閉 App 再打開，新組別先會生效。'),
            const Text('組別只喺呢度顯示，請唔好寫喺 PI 會睇到嘅地方。'),
            const SizedBox(height: 16),
            OutlinedButton(
              key: const Key('enroll_next'),
              onPressed: onNext,
              child: const Text('登記下一位'),
            ),
          ],
        ),
      ),
    );
  }
}
