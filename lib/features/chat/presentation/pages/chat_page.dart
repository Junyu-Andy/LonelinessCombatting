import 'package:flutter/material.dart';

import '../../data/chat_backend.dart';
import '../../data/chat_models.dart';
import '../widgets/persona_avatar.dart';

/// Per-persona chat surface. Bubbles fade-and-slide in, the persona avatar
/// flies in via [Hero] from the landing card, and a typing indicator
/// renders while [ChatBackend.reply] is awaiting.
///
/// Voice input is currently a stub — pressing the mic shows a recording
/// pulse for ~1s and then drops a "(語音輸入：未錄到聲音)" placeholder
/// into the text field, leaving room to wire `speech_to_text` later.
class ChatPage extends StatefulWidget {
  final ChatPersona persona;
  final ChatBackend? backend;

  const ChatPage({super.key, required this.persona, this.backend});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  late final ChatBackend _backend = widget.backend ?? DeepseekChatBackend();
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  bool _waiting = false;
  bool _recording = false;

  @override
  void initState() {
    super.initState();
    // Greet is set in didChangeDependencies once locale is available.
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_messages.isEmpty) {
      final isEn =
          Localizations.localeOf(context).languageCode == 'en';
      final greeting = switch (widget.persona) {
        ChatPersona.casual => isEn
            ? 'Hi~ How's your day going? Feel free to share anything.'
            : '嗨～今日過得點？傾乜都得。',
        ChatPersona.consult => isEn
            ? 'Hello. I'm here. What would you like to talk about today?'
            : '你好。我喺度。今日有啲乜想傾？',
        ChatPersona.faq => isEn
            ? 'Hi! I'm Xiao Zhu. Ask me anything about this app — features, settings, privacy, or more.'
            : '你好！我係小助。你可以問關於呢個 app 嘅功能、設定、私隱或者其他問題。',
      };
      _messages.add(ChatMessage(
        text: greeting,
        fromUser: false,
        sentAt: DateTime.now(),
      ));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _waiting) return;
    _controller.clear();
    setState(() {
      _messages.add(ChatMessage(
        text: trimmed,
        fromUser: true,
        sentAt: DateTime.now(),
      ));
      _waiting = true;
    });
    _scrollToBottom();
    try {
      final reply = await _backend.reply(
        persona: widget.persona,
        history: List.unmodifiable(_messages),
        userMessage: trimmed,
      );
      if (!mounted) return;
      setState(() {
        _messages.add(ChatMessage(
          text: reply,
          fromUser: false,
          sentAt: DateTime.now(),
        ));
        _waiting = false;
      });
      _scrollToBottom();
    } catch (_) {
      if (!mounted) return;
      final isEn = Localizations.localeOf(context).languageCode == 'en';
      setState(() {
        _messages.add(ChatMessage(
          text: isEn
              ? 'Sorry, connection failed. Please try again later.'
              : '對唔住，依家連唔到。試多次，或者過陣再嚟。',
          fromUser: false,
          sentAt: DateTime.now(),
        ));
        _waiting = false;
      });
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent + 120,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _toggleVoice() async {
    if (_recording) {
      setState(() => _recording = false);
      return;
    }
    setState(() => _recording = true);
    // TODO(speech): replace with `speech_to_text` once we add the dep.
    await Future.delayed(const Duration(milliseconds: 1100));
    if (!mounted) return;
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final placeholder =
        isEn ? '(Voice input: pending backend support)' : '（語音輸入：待後台支援）';
    setState(() {
      _recording = false;
      _controller.text = _controller.text.isEmpty
          ? placeholder
          : '${_controller.text} $placeholder';
      _controller.selection = TextSelection.fromPosition(
        TextPosition(offset: _controller.text.length),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final spec = personaVisual(widget.persona);
    return Scaffold(
      backgroundColor: spec.bubbleColor.withValues(alpha: 0.35),
      appBar: AppBar(
        backgroundColor: spec.bubbleColor,
        surfaceTintColor: Colors.transparent,
        title: Row(
          children: [
            PersonaAvatar(persona: widget.persona, size: 40),
            const SizedBox(width: 10),
            Text(
              spec.displayName,
              style: TextStyle(
                color: spec.accent,
                fontWeight: FontWeight.w700,
                fontSize: 22,
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              itemCount: _messages.length + (_waiting ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == _messages.length) {
                  return _TypingIndicator(spec: spec);
                }
                final m = _messages[index];
                return _Bubble(
                  message: m,
                  spec: spec,
                  // Only animate the just-arrived bubble, not the entire
                  // history every time we rebuild.
                  isLatest: index == _messages.length - 1,
                );
              },
            ),
          ),
          _InputBar(
            controller: _controller,
            spec: spec,
            recording: _recording,
            disabled: _waiting,
            onSend: _send,
            onMic: _toggleVoice,
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final ChatMessage message;
  final PersonaVisual spec;
  final bool isLatest;

  const _Bubble({
    required this.message,
    required this.spec,
    required this.isLatest,
  });

  @override
  Widget build(BuildContext context) {
    final fromUser = message.fromUser;
    final bg = fromUser ? spec.accent : Colors.white;
    final fg = fromUser ? Colors.white : Colors.black87;
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(20),
      topRight: const Radius.circular(20),
      bottomLeft: Radius.circular(fromUser ? 20 : 6),
      bottomRight: Radius.circular(fromUser ? 6 : 20),
    );
    final bubble = ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.78,
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: radius,
          border: fromUser ? null : Border.all(color: spec.accent.withValues(alpha: 0.2)),
        ),
        child: Text(
          message.text,
          style: TextStyle(
            color: fg,
            fontSize: 18,
            height: 1.4,
          ),
        ),
      ),
    );
    final aligned = Align(
      alignment: fromUser ? Alignment.centerRight : Alignment.centerLeft,
      child: bubble,
    );
    if (!isLatest) return aligned;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
      builder: (context, t, child) {
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, (1 - t) * 8),
            child: child,
          ),
        );
      },
      child: aligned,
    );
  }
}

class _TypingIndicator extends StatefulWidget {
  final PersonaVisual spec;

  const _TypingIndicator({required this.spec});

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ac = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _ac.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: widget.spec.accent.withValues(alpha: 0.25)),
        ),
        child: AnimatedBuilder(
          animation: _ac,
          builder: (context, _) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (i) {
                final phase = (_ac.value * 3 + i) % 3;
                final t = (1 - (phase - 1).abs()).clamp(0.3, 1.0);
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: widget.spec.accent.withValues(alpha: t),
                    shape: BoxShape.circle,
                  ),
                );
              }),
            );
          },
        ),
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final PersonaVisual spec;
  final bool recording;
  final bool disabled;
  final ValueChanged<String> onSend;
  final VoidCallback onMic;

  const _InputBar({
    required this.controller,
    required this.spec,
    required this.recording,
    required this.disabled,
    required this.onSend,
    required this.onMic,
  });

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(
            top: BorderSide(color: spec.accent.withValues(alpha: 0.2)),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _MicButton(
              accent: spec.accent,
              recording: recording,
              onPressed: onMic,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: controller,
                maxLines: 4,
                minLines: 1,
                enabled: !disabled,
                textInputAction: TextInputAction.send,
                onSubmitted: onSend,
                decoration: InputDecoration(
                  hintText: recording
                      ? (isEn ? 'Recording…' : '錄緊音…')
                      : (isEn ? 'Type or tap mic to speak…' : '寫低或者撳咪講…'),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide(color: spec.accent.withValues(alpha: 0.4)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide(color: spec.accent.withValues(alpha: 0.4)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide(color: spec.accent, width: 2),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: disabled ? null : () => onSend(controller.text),
              style: FilledButton.styleFrom(
                shape: const CircleBorder(),
                padding: const EdgeInsets.all(14),
                backgroundColor: spec.accent,
              ),
              child: const Icon(Icons.arrow_upward_rounded,
                  color: Colors.white, size: 24),
            ),
          ],
        ),
      ),
    );
  }
}

class _MicButton extends StatefulWidget {
  final Color accent;
  final bool recording;
  final VoidCallback onPressed;

  const _MicButton({
    required this.accent,
    required this.recording,
    required this.onPressed,
  });

  @override
  State<_MicButton> createState() => _MicButtonState();
}

class _MicButtonState extends State<_MicButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void didUpdateWidget(covariant _MicButton old) {
    super.didUpdateWidget(old);
    if (widget.recording && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    } else if (!widget.recording) {
      _pulse.stop();
      _pulse.reset();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        final scale = widget.recording ? 1 + 0.08 * _pulse.value : 1.0;
        return Transform.scale(
          scale: scale,
          child: IconButton(
            onPressed: widget.onPressed,
            tooltip: widget.recording ? 'Stop' : 'Voice input',
            icon: Icon(
              widget.recording ? Icons.stop_circle : Icons.mic_none_rounded,
              color: widget.accent,
              size: 30,
            ),
          ),
        );
      },
    );
  }
}
