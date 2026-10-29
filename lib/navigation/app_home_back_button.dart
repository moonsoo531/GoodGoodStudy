import 'package:flutter/material.dart';

import 'app_navigation.dart';
import 'navigation_strings.dart';

class AppHomeBackButton extends StatelessWidget {
  const AppHomeBackButton({super.key});

  @override
  Widget build(BuildContext context) {
    final navigation = AppNavigationScope.maybeOf(context);
    if (navigation == null) return const SizedBox.shrink();
    return IconButton(
      key: const ValueKey('app-home-back'),
      tooltip: NavigationStrings(context).backToHome,
      onPressed: navigation.isSwitching
          ? null
          : () async {
              await navigation.navigate(AppSection.home);
            },
      icon: const BackButtonIcon(),
    );
  }
}
