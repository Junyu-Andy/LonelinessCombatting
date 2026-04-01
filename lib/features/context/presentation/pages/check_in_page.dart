import 'package:flutter/material.dart';

class CheckInPage extends StatefulWidget {
  const CheckInPage({super.key});

  @override
  State<CheckInPage> createState() => _CheckInPageState();
}

class _CheckInPageState extends State<CheckInPage> {
  double _mood = 3;
  double _loneliness = 3;
  double _socialEnergy = 3;
  final TextEditingController _recentExperienceController =
      TextEditingController();

  @override
  void dispose() {
    _recentExperienceController.dispose();
    super.dispose();
  }

  String _scoreLabel(double value) {
    switch (value.toInt()) {
      case 1:
        return '低';
      case 2:
        return '偏低';
      case 3:
        return '中等';
      case 4:
        return '偏高';
      case 5:
        return '高';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('快速 Check-in'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            '呢頁模擬一個低負擔 check-in，用幾個簡單輸入快速捉到當下狀態。',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 24),
          _SliderSection(
            title: '今日心情',
            value: _mood,
            label: _scoreLabel(_mood),
            onChanged: (value) {
              setState(() {
                _mood = value;
              });
            },
          ),
          const SizedBox(height: 20),
          _SliderSection(
            title: '今日孤獨感',
            value: _loneliness,
            label: _scoreLabel(_loneliness),
            onChanged: (value) {
              setState(() {
                _loneliness = value;
              });
            },
          ),
          const SizedBox(height: 20),
          _SliderSection(
            title: '今日社交能量',
            value: _socialEnergy,
            label: _scoreLabel(_socialEnergy),
            onChanged: (value) {
              setState(() {
                _socialEnergy = value;
              });
            },
          ),
          const SizedBox(height: 24),
          Text(
            '最近社交經驗',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _recentExperienceController,
            maxLines: 4,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: '例如：今日同朋友有短訊來往，但未真正傾到心事。',
            ),
          ),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '目前摘要',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Chip(label: Text('心情 ${_mood.toInt()}/5')),
                      Chip(label: Text('孤獨感 ${_loneliness.toInt()}/5')),
                      Chip(label: Text('社交能量 ${_socialEnergy.toInt()}/5')),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _recentExperienceController.text.isEmpty
                        ? '未填寫最近社交經驗。'
                        : _recentExperienceController.text,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SliderSection extends StatelessWidget {
  final String title;
  final double value;
  final String label;
  final ValueChanged<double> onChanged;

  const _SliderSection({
    required this.title,
    required this.value,
    required this.label,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('目前：$label'),
            Slider(
              value: value,
              min: 1,
              max: 5,
              divisions: 4,
              label: value.toInt().toString(),
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}