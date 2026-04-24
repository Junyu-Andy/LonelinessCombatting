import 'dart:async';
import 'package:flutter/material.dart';

enum _BreathPhase { inhale, hold, exhale }

class CalmPage extends StatefulWidget {
  const CalmPage({super.key});

  @override
  State<CalmPage> createState() => _CalmPageState();
}

class _CalmPageState extends State<CalmPage>
    with SingleTickerProviderStateMixin {
  static const _inhaleSeconds = 4;
  static const _holdSeconds = 4;
  static const _exhaleSeconds = 6;
  static const _totalCycles = 4;

  late final AnimationController _controller;
  _BreathPhase _phase = _BreathPhase.inhale;
  int _cycleCount = 0;
  int _secondsLeft = _inhaleSeconds;
  Timer? _ticker;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: _inhaleSeconds),
    );
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _start() {
    setState(() {
      _running = true;
      _cycleCount = 0;
      _phase = _BreathPhase.inhale;
      _secondsLeft = _inhaleSeconds;
    });
    _runPhase();
  }

  void _stop() {
    _ticker?.cancel();
    _controller.stop();
    setState(() {
      _running = false;
    });
  }

  void _runPhase() {
    final int duration;
    switch (_phase) {
      case _BreathPhase.inhale:
        duration = _inhaleSeconds;
        _controller.duration = const Duration(seconds: _inhaleSeconds);
        _controller.forward(from: 0);
        break;
      case _BreathPhase.hold:
        duration = _holdSeconds;
        break;
      case _BreathPhase.exhale:
        duration = _exhaleSeconds;
        _controller.duration = const Duration(seconds: _exhaleSeconds);
        _controller.reverse(from: 1);
        break;
    }

    setState(() {
      _secondsLeft = duration;
    });

    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        _secondsLeft -= 1;
      });
      if (_secondsLeft <= 0) {
        timer.cancel();
        _advance();
      }
    });
  }

  void _advance() {
    if (!mounted) return;
    if (_phase == _BreathPhase.inhale) {
      setState(() => _phase = _BreathPhase.hold);
      _runPhase();
      return;
    }
    if (_phase == _BreathPhase.hold) {
      setState(() => _phase = _BreathPhase.exhale);
      _runPhase();
      return;
    }
    final nextCycle = _cycleCount + 1;
    if (nextCycle >= _totalCycles) {
      setState(() {
        _running = false;
        _cycleCount = nextCycle;
      });
      return;
    }
    setState(() {
      _cycleCount = nextCycle;
      _phase = _BreathPhase.inhale;
    });
    _runPhase();
  }

  String get _phaseLabel {
    switch (_phase) {
      case _BreathPhase.inhale:
        return '慢慢吸氣';
      case _BreathPhase.hold:
        return '停一停';
      case _BreathPhase.exhale:
        return '慢慢呼氣';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('靜一靜'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        children: [
          Text(
            '如果覺得心煩、心跳快、或者唔舒服，可以跟住下面嘅節奏呼吸幾次。',
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
              child: Column(
                children: [
                  SizedBox(
                    height: 260,
                    child: AnimatedBuilder(
                      animation: _controller,
                      builder: (context, child) {
                        final base = 140.0;
                        final range = 100.0;
                        final size = base + range * _controller.value;
                        return Center(
                          child: Container(
                            width: size,
                            height: size,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primaryContainer,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: theme.colorScheme.primary,
                                width: 4,
                              ),
                            ),
                            alignment: Alignment.center,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _running ? _phaseLabel : '準備好就開始',
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    color:
                                        theme.colorScheme.onPrimaryContainer,
                                  ),
                                ),
                                if (_running) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    '$_secondsLeft',
                                    style: TextStyle(
                                      fontSize: 44,
                                      fontWeight: FontWeight.w700,
                                      color: theme
                                          .colorScheme.onPrimaryContainer,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _running
                        ? '第 ${_cycleCount + 1} / $_totalCycles 次'
                        : '總共 $_totalCycles 次循環，大約 1 分鐘。',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _running ? _stop : _start,
                      icon: Icon(
                        _running ? Icons.stop_rounded : Icons.play_arrow_rounded,
                        size: 28,
                      ),
                      label: Text(_running ? '停低' : '開始'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 28),
          _SectionHeader(
            icon: Icons.visibility_outlined,
            title: '5-4-3-2-1 定神練習',
          ),
          const SizedBox(height: 14),
          const _GroundingCard(),
          const SizedBox(height: 28),
          _SectionHeader(
            icon: Icons.tips_and_updates_outlined,
            title: '其他溫柔嘅方法',
          ),
          const SizedBox(height: 14),
          const _TipCard(
            icon: Icons.local_drink_outlined,
            title: '飲一啖暖水',
            body: '慢慢啖住，感受水流過喉嚨，畀自己幾秒鐘。',
          ),
          const SizedBox(height: 12),
          const _TipCard(
            icon: Icons.pan_tool_outlined,
            title: '搓吓雙手',
            body: '磨擦雙手 10 秒鐘，然後將暖咗嘅手放喺心口。',
          ),
          const SizedBox(height: 12),
          const _TipCard(
            icon: Icons.music_note_outlined,
            title: '聽一首熟悉嘅歌',
            body: '熟悉嘅旋律通常可以令情緒沉澱落嚟。',
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;

  const _SectionHeader({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 30, color: theme.colorScheme.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: theme.textTheme.titleLarge,
          ),
        ),
      ],
    );
  }
}

class _GroundingCard extends StatelessWidget {
  const _GroundingCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = const [
      (5, '樣嘢你見到', Icons.remove_red_eye_outlined),
      (4, '樣嘢你摸到', Icons.back_hand_outlined),
      (3, '種聲音你聽到', Icons.hearing_outlined),
      (2, '種味道你聞到', Icons.air_outlined),
      (1, '種味覺你感受到', Icons.restaurant_outlined),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '慢慢望一望四周，嘗試逐樣講出：',
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 14),
            ...items.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${item.$1}',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Icon(
                      item.$3,
                      size: 26,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        item.$2,
                        style: theme.textTheme.bodyLarge,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TipCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _TipCard({
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                icon,
                size: 30,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    body,
                    style: theme.textTheme.bodyLarge,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
