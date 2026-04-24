import 'package:flutter/material.dart';
import '../../../../shared/widgets/figure_placeholder.dart';

class OnboardingSlide extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final List<String> bullets;
  final String? figureDescription;

  const OnboardingSlide({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.bullets = const [],
    this.figureDescription,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 16, 28, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          Center(
            child: Container(
              width: 128,
              height: 128,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(28),
              ),
              child: Icon(
                icon,
                size: 72,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ),
          const SizedBox(height: 28),
          Text(
            title,
            style: theme.textTheme.headlineLarge,
          ),
          const SizedBox(height: 14),
          Text(
            body,
            style: theme.textTheme.bodyLarge,
          ),
          if (figureDescription != null) ...[
            const SizedBox(height: 20),
            FigurePlaceholder(
              description: figureDescription!,
              height: 130,
              icon: icon,
            ),
          ],
          if (bullets.isNotEmpty) ...[
            const SizedBox(height: 28),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: bullets
                      .map(
                        (item) => Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Icon(
                                  Icons.check_circle,
                                  size: 28,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Text(
                                  item,
                                  style: theme.textTheme.bodyLarge,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
