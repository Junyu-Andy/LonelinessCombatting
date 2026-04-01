import 'package:flutter/material.dart';

class ReflectionPage extends StatelessWidget {
  const ReflectionPage({super.key});

  @override
  Widget build(BuildContext context) {
    final items = [
      const _ReflectionItem(
        title: '同朋友短訊來往',
        when: '尋日',
        feeling: '有少少連結，但未夠深入',
        gap: '對方有回覆，但自己冇再展開話題。',
      ),
      const _ReflectionItem(
        title: '家庭群組互動',
        when: '三日前',
        feeling: '有存在感，但唔算被理解',
        gap: '互動比較表面，冇講到自己真正狀態。',
      ),
      const _ReflectionItem(
        title: '同事午飯閒聊',
        when: '今個星期',
        feeling: '氣氛輕鬆',
        gap: '有陪伴感，但關係未去到可以傾私人事。',
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('互動反思'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            '呢頁用來回顧最近接觸，幫你分清楚「有互動」同「有連結感」未必係同一回事。',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '反思提示',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  const Text('1. 呢次互動入面，邊一刻最有被連結嘅感覺？'),
                  const SizedBox(height: 8),
                  const Text('2. 有冇邊個位你其實想再多行一步，但最後冇做？'),
                  const SizedBox(height: 8),
                  const Text('3. 下次如果想拉近少少距離，最細嘅下一步可以係乜？'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          ...items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Chip(label: Text(item.when)),
                      const SizedBox(height: 12),
                      Text('感受：${item.feeling}'),
                      const SizedBox(height: 8),
                      Text('落差：${item.gap}'),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReflectionItem {
  final String title;
  final String when;
  final String feeling;
  final String gap;

  const _ReflectionItem({
    required this.title,
    required this.when,
    required this.feeling,
    required this.gap,
  });
}