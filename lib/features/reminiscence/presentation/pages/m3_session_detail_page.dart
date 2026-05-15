import 'package:flutter/material.dart';

import '../../../../app/app_settings_scope.dart';
import '../../../../core/arm/arm_scope.dart';
import '../../../auth/presentation/auth_service_scope.dart';
import '../../data/m3_session_store.dart';
import '../../data/reminiscence_themes.dart';

/// Detail view for an already-completed M3 session.
///
/// Read-only by default. Arm A users get a "Re-edit" affordance that
/// reopens the editable text field; the *original* LLM summary is
/// preserved on disk (immutable) and shown beneath the edited version.
/// Arm B has no editor; users see their own raw note.
class M3SessionDetailPage extends StatefulWidget {
  final ReminiscenceTheme theme;
  const M3SessionDetailPage({super.key, required this.theme});

  @override
  State<M3SessionDetailPage> createState() => _M3SessionDetailPageState();
}

class _M3SessionDetailPageState extends State<M3SessionDetailPage> {
  M3SessionDoc? _doc;
  bool _loading = true;
  bool _editing = false;
  bool _saving = false;
  final _editCtrl = TextEditingController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_doc == null && _loading) _load();
  }

  @override
  void dispose() {
    _editCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final profile = AppSettingsScope.read(context).profile;
    final auth = AuthServiceScope.of(context);
    if (profile == null) {
      setState(() => _loading = false);
      return;
    }
    final store = M3SessionStore(available: auth.available);
    final doc = await store.read(
      uid: profile.uid,
      weekIndex: widget.theme.weekIndex,
    );
    if (!mounted) return;
    setState(() {
      _doc = doc;
      _loading = false;
      _editCtrl.text = doc?.callbackSummary ?? '';
    });
  }

  Future<void> _saveEdit() async {
    final profile = AppSettingsScope.read(context).profile;
    final auth = AuthServiceScope.of(context);
    final newText = _editCtrl.text.trim();
    if (profile == null || newText.isEmpty) return;
    setState(() => _saving = true);
    final store = M3SessionStore(available: auth.available);
    await store.reEditSummary(
      uid: profile.uid,
      weekIndex: widget.theme.weekIndex,
      newEdited: newText,
    );
    final fresh = await store.read(
      uid: profile.uid,
      weekIndex: widget.theme.weekIndex,
    );
    if (!mounted) return;
    setState(() {
      _doc = fresh;
      _editing = false;
      _saving = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          Localizations.localeOf(context).languageCode == 'en'
              ? 'Saved ✓'
              : '已儲存 ✓',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);
    final title = isEn ? widget.theme.titleEn : widget.theme.titleZh;

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final doc = _doc;
    if (doc == null || doc.callbackSummary == null) {
      return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              isEn
                  ? 'This session hasn\'t been completed yet.'
                  : '呢節 session 仲未完成。',
              style: theme.textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final canReEdit = Arm.isA(context) && !_editing;
    final original = doc.endSummaryOriginal;
    final edited = doc.endSummaryEdited;
    final isEdited = doc.endSummaryUserEdited;

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (canReEdit)
            TextButton.icon(
              onPressed: () => setState(() {
                _editing = true;
                _editCtrl.text = doc.callbackSummary ?? '';
              }),
              icon: const Icon(Icons.edit_outlined),
              label: Text(isEn ? 'Re-edit' : '編輯'),
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            if (_editing) ...[
              Text(
                isEn ? 'Your version' : '你嘅版本',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _editCtrl,
                maxLines: null,
                minLines: 6,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontSize: 20,
                  height: 1.8,
                ),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _saving
                          ? null
                          : () => setState(() {
                                _editing = false;
                                _editCtrl.text = doc.callbackSummary ?? '';
                              }),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(isEn ? 'Cancel' : '取消'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _saving ? null : _saveEdit,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(isEn ? 'Save' : '儲存'),
                      ),
                    ),
                  ),
                ],
              ),
            ] else ...[
              if (isEdited && edited != null) ...[
                _SummarySection(
                  label: isEn ? 'Your version' : '你嘅版本',
                  body: edited,
                  emphasis: true,
                ),
                const SizedBox(height: 16),
              ],
              if (original != null)
                _SummarySection(
                  label: isEdited
                      ? (isEn ? 'Original (you read this)' : '系統原版（你已睇過）')
                      : (isEn ? 'Summary' : '小結'),
                  body: original,
                  emphasis: !isEdited,
                ),
              if (doc.completedAt != null) ...[
                const SizedBox(height: 16),
                Text(
                  isEn
                      ? 'Completed ${_formatDate(doc.completedAt!, isEn)}'
                      : '完成於 ${_formatDate(doc.completedAt!, isEn)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime d, bool isEn) {
    final local = d.toLocal();
    if (isEn) return '${local.year}-${_two(local.month)}-${_two(local.day)}';
    return '${local.year} 年 ${local.month} 月 ${local.day} 日';
  }

  String _two(int n) => n < 10 ? '0$n' : '$n';
}

class _SummarySection extends StatelessWidget {
  final String label;
  final String body;
  final bool emphasis;
  const _SummarySection({
    required this.label,
    required this.body,
    required this.emphasis,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: emphasis
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.45)
            : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: theme.textTheme.bodyLarge?.copyWith(
              height: 1.6,
              fontSize: 18,
            ),
          ),
        ],
      ),
    );
  }
}
