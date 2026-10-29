import 'package:flutter/material.dart';

import 'app_navigation.dart';
import 'navigation_strings.dart';

IconData sectionIcon(AppSection section) => switch (section) {
  AppSection.home => Icons.home_outlined,
  AppSection.study => Icons.menu_book_rounded,
  AppSection.quiz => Icons.fact_check_outlined,
  AppSection.player => Icons.play_circle_outline_rounded,
};

class AppSectionMenuButton extends StatelessWidget {
  const AppSectionMenuButton({super.key});

  @override
  Widget build(BuildContext context) {
    final navigation = AppNavigationScope.maybeOf(context);
    if (navigation == null) return const SizedBox.shrink();
    final strings = NavigationStrings(context);
    return IconButton(
      key: const ValueKey('app-section-menu'),
      tooltip: strings.switchPage,
      onPressed: navigation.isSwitching
          ? null
          : () async {
              final navigator = Navigator.of(context);
              final route = DialogRoute<AppSection>(
                context: context,
                builder: (dialogContext) => SimpleDialog(
                  title: Text(NavigationStrings(dialogContext).switchPage),
                  children: [
                    for (final section in AppSection.values)
                      ListTile(
                        key: ValueKey('app-section-${section.name}'),
                        leading: Icon(sectionIcon(section)),
                        title: Text(
                          NavigationStrings(dialogContext).label(section),
                        ),
                        trailing: navigation.section == section
                            ? const Icon(Icons.check_rounded)
                            : null,
                        selected: navigation.section == section,
                        onTap: () => Navigator.of(dialogContext).pop(section),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                      child: TextButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        child: Text(NavigationStrings(dialogContext).close),
                      ),
                    ),
                  ],
                ),
              );
              final section = await navigator.push<AppSection>(route);
              await route.completed;
              if (section != null && context.mounted) {
                await navigation.navigate(section);
              }
            },
      icon: const Icon(Icons.menu_rounded),
    );
  }
}
