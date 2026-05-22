import 'package:flutter/material.dart';

import '../../data/education_library.dart';
import 'education_article_page.dart';

/// M8 library landing — identical in both arms (spec: library content
/// is identical; only the "Ask me about this" dialogue is Arm A).
class EducationLibraryPage extends StatelessWidget {
  const EducationLibraryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(isEn ? 'Read a little' : '讀少少')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            Text(
              isEn
                  ? 'Short pieces, plain language. Take what helps, skip '
                      'the rest.'
                  : '每篇短短，平實啲講。睇啱嘅，唔啱就過。',
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
            // Research Review v2 Item 1: filter by enabled flag so individual
            // articles can be hidden without a code push during Phase A.
            for (final a in EducationLibrary.articles.where((a) => a.enabled))
              _ArticleCard(
                article: a,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => EducationArticlePage(article: a),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ArticleCard extends StatelessWidget {
  final EducationArticle article;
  final VoidCallback onTap;
  const _ArticleCard({required this.article, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Icon(Icons.menu_book_outlined,
                    size: 28, color: theme.colorScheme.primary),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    isEn ? article.titleEn : article.titleZh,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                Icon(Icons.chevron_right_rounded,
                    color: theme.colorScheme.primary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
