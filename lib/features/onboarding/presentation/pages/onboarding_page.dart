import 'package:flutter/material.dart';
import '../../../../app/main_shell.dart';
import '../../../../l10n/app_localizations.dart';
import '../widgets/onboarding_slide.dart';

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final PageController _pageController = PageController();
  int _currentIndex = 0;

  void _goToPage(int index) {
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
    );
  }

  void _enterDemo() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => const MainShell(),
      ),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    final slides = [
      _SlideData(
        icon: Icons.handshake_outlined,
        title: l10n.onboardingWelcomeTitle,
        body: l10n.onboardingWelcomeBody,
      ),
      _SlideData(
        icon: Icons.lightbulb_outline,
        title: l10n.onboardingHelpTitle,
        body: l10n.onboardingHelpBody,
      ),
      _SlideData(
        icon: Icons.shield_outlined,
        title: l10n.onboardingBoundaryTitle,
        body: l10n.onboardingBoundaryBody,
        bullets: [
          l10n.onboardingBoundaryItemOne,
          l10n.onboardingBoundaryItemTwo,
          l10n.onboardingBoundaryItemThree,
        ],
      ),
      _SlideData(
        icon: Icons.rocket_launch_outlined,
        title: l10n.onboardingStartTitle,
        body: l10n.onboardingStartBody,
      ),
    ];

    final isLastPage = _currentIndex == slides.length - 1;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (index) {
                  setState(() {
                    _currentIndex = index;
                  });
                },
                children: slides
                    .map(
                      (slide) => OnboardingSlide(
                        icon: slide.icon,
                        title: slide.title,
                        body: slide.body,
                        bullets: slide.bullets,
                      ),
                    )
                    .toList(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      slides.length,
                      (index) => AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: _currentIndex == index ? 24 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: _currentIndex == index
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.outlineVariant,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      if (_currentIndex > 0)
                        TextButton(
                          onPressed: () => _goToPage(_currentIndex - 1),
                          child: Text(l10n.back),
                        )
                      else
                        const SizedBox(width: 72),
                      const Spacer(),
                      FilledButton(
                        onPressed: () {
                          if (isLastPage) {
                            _enterDemo();
                            return;
                          }
                          _goToPage(_currentIndex + 1);
                        },
                        child: Text(isLastPage ? l10n.enterDemo : l10n.next),
                      ),
                    ],
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

class _SlideData {
  final IconData icon;
  final String title;
  final String body;
  final List<String> bullets;

  const _SlideData({
    required this.icon,
    required this.title,
    required this.body,
    this.bullets = const [],
  });
}