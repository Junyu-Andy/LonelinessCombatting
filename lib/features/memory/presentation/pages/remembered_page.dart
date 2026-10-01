/// 「我記得嘅嘢」 — the user's view of memory v1.
///
/// Lists everything the companions may draw on, grouped the way the user
/// would think about it, with large text and one tap to delete. Sensitive
/// items the server extracted wait here for an explicit go-ahead before
/// any companion uses them. The page can only read, delete and confirm
/// (firestore.rules); it can never add or edit what is remembered.
library;

import 'package:flutter/material.dart';

import '../../../../app/app_settings_scope.dart';
import '../../../../core/agents/agent_registry.dart';
import '../../../../core/memory/memory_mode.dart';
import '../../../../core/memory/memory_v1_service.dart';
import '../../../../shared/widgets/app_confirm_dialog.dart';

class RememberedPage extends StatelessWidget {
  const RememberedPage({super.key, this.service = const MemoryV1Service()});

  final MemoryV1Service service;

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final profile = AppSettingsScope.of(context).profile;
    return Scaffold(
      appBar: AppBar(title: Text(isEn ? 'What I remember' : '我記得嘅嘢')),
      body: SafeArea(
        child: profile == null
            ? _Empty(text: isEn ? 'Please sign in first.' : '請先登入。')
            : !MemoryModes.of(profile).isV1
                ? _Empty(
                    text: isEn
                        ? 'Memory is off. Nothing new is being remembered.'
                        : '記憶已經熄咗，而家唔會記住新嘅嘢。',
                  )
                : _Lists(uid: profile.uid, service: service),
      ),
    );
  }
}

class _Lists extends StatelessWidget {
  const _Lists({required this.uid, required this.service});

  final String uid;
  final MemoryV1Service service;

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    return StreamBuilder<List<MemoryItem>>(
      stream: service.watch(uid, MemoryLayer.fact),
      builder: (context, facts) => StreamBuilder<List<MemoryItem>>(
        stream: service.watch(uid, MemoryLayer.followup),
        builder: (context, followups) => StreamBuilder<List<MemoryItem>>(
          stream: service.watch(uid, MemoryLayer.summary),
          builder: (context, summaries) {
            final f = facts.data ?? const <MemoryItem>[];
            final pending = f.where((i) => i.pendingConfirmation).toList();
            final active = f.where((i) => !i.pendingConfirmation).toList();
            final fu = followups.data ?? const <MemoryItem>[];
            final su = summaries.data ?? const <MemoryItem>[];
            if (facts.connectionState == ConnectionState.waiting &&
                !facts.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            if (pending.isEmpty && active.isEmpty && fu.isEmpty &&
                su.isEmpty) {
              return _Empty(
                text: isEn
                    ? 'Nothing remembered yet.'
                    : '暫時未記住任何嘢。',
              );
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              children: [
                if (pending.isNotEmpty) ...[
                  _Header(
                    isEn ? 'Should I remember these?' : '呢啲要唔要記住？',
                    isEn
                        ? 'Nobody uses these until you say yes.'
                        : '你話好之前，冇人會用到呢啲。',
                  ),
                  for (final i in pending)
                    _ItemCard(item: i, uid: uid, service: service,
                        confirmable: true),
                ],
                if (active.isNotEmpty) ...[
                  _Header(isEn ? 'About you' : '關於你嘅嘢', null),
                  for (final i in active)
                    _ItemCard(item: i, uid: uid, service: service),
                ],
                if (fu.isNotEmpty) ...[
                  _Header(isEn ? 'Things to ask about' : '記住要關心嘅事', null),
                  for (final i in fu)
                    _ItemCard(item: i, uid: uid, service: service),
                ],
                if (su.isNotEmpty) ...[
                  _Header(isEn ? 'Past chats' : '之前傾過', null),
                  for (final i in su)
                    _ItemCard(item: i, uid: uid, service: service),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.title, this.subtitle);

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700)),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle!, style: theme.textTheme.bodyLarge),
          ],
        ],
      ),
    );
  }
}

class _ItemCard extends StatelessWidget {
  const _ItemCard({
    required this.item,
    required this.uid,
    required this.service,
    this.confirmable = false,
  });

  final MemoryItem item;
  final String uid;
  final MemoryV1Service service;
  final bool confirmable;

  String _agentName(BuildContext context, bool isEn) {
    final agent = AgentRegistry.tryById(item.agentId);
    if (agent == null) return '';
    final variant = agent.resolveVariant(
        AppSettingsScope.read(context).profile?.ahJanAhBakVariant);
    return isEn ? variant.displayNameEn : variant.displayNameZh;
  }

  Future<void> _delete(BuildContext context, bool isEn) async {
    final ok = await showAppConfirm(
      context: context,
      title: isEn ? 'Forget this?' : '唔好再記住呢樣？',
      message: item.title,
      confirmLabel: isEn ? 'Forget' : '唔好記',
      destructive: true,
    );
    if (ok) await service.delete(uid, item);
  }

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);
    final agent = AgentRegistry.tryById(item.agentId);
    final who = _agentName(context, isEn);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.title,
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600)),
                      if (item.body.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(item.body, style: theme.textTheme.bodyLarge),
                      ],
                      if (who.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          isEn ? 'Told to $who' : '同$who講嘅',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: agent?.accentColor ??
                                theme.colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (!confirmable)
                  IconButton(
                    iconSize: 28,
                    tooltip: isEn ? 'Forget' : '唔好記',
                    icon: const Icon(Icons.delete_outline_rounded),
                    onPressed: () => _delete(context, isEn),
                  ),
              ],
            ),
            if (confirmable) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  FilledButton(
                    onPressed: () => service.confirm(uid, item),
                    child: Text(isEn ? 'Yes, remember' : '好，記住'),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton(
                    onPressed: () => _delete(context, isEn),
                    child: Text(isEn ? 'No, forget it' : '唔好記'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ),
    );
  }
}
