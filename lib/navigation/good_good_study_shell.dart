import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'app_navigation.dart';
import 'app_section_menu_button.dart';
import 'navigation_strings.dart';

/// Module builders must create independent pages; only the selected builder is
/// mounted. Audio-owning pages register exit guards and shutdown futures.
class GoodGoodStudyShell extends StatefulWidget {
  const GoodGoodStudyShell({
    super.key,
    required this.controller,
    required this.builders,
    this.iconAsset = 'assets/branding/goodgoodstudy-icon.png',
    this.phonePlayback = false,
  });
  final AppNavigationController controller;
  final Map<AppSection, WidgetBuilder> builders;
  final String? iconAsset;
  final bool phonePlayback;
  @override
  State<GoodGoodStudyShell> createState() => _GoodGoodStudyShellState();
}

class _GoodGoodStudyShellState extends State<GoodGoodStudyShell> {
  @override
  void initState() {
    super.initState();
    if (!widget.controller.isReady) unawaited(widget.controller.load());
  }

  @override
  Widget build(BuildContext context) => AppNavigationScope(
    controller: widget.controller,
    child: Builder(
      builder: (context) {
        final navigation = AppNavigationScope.of(context);
        final strings = NavigationStrings(context);
        if (!navigation.isReady || !navigation.isModuleMounted) {
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(
                    navigation.isReady ? strings.switching : strings.loading,
                  ),
                ],
              ),
            ),
          );
        }
        if (navigation.section == AppSection.home) {
          return _HomePage(
            iconAsset: widget.iconAsset,
            phonePlayback: widget.phonePlayback,
          );
        }
        final builder = widget.builders[navigation.section];
        return KeyedSubtree(
          key: ValueKey('section-${navigation.section.name}'),
          child:
              builder?.call(context) ??
              _HomePage(
                iconAsset: widget.iconAsset,
                phonePlayback: widget.phonePlayback,
              ),
        );
      },
    ),
  );
}

class _HomePage extends StatelessWidget {
  const _HomePage({required this.iconAsset, required this.phonePlayback});
  final String? iconAsset;
  final bool phonePlayback;

  @override
  Widget build(BuildContext context) {
    final strings = NavigationStrings(context);
    final navigation = AppNavigationScope.of(context);
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text(
          'GoodGoodStudy',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: const [
          AppSectionMenuButton(),
          ThemeMenuButton(),
          SizedBox(width: 12),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1120),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (navigation.errorMessage != null) ...[
                      Material(
                        color: colors.errorContainer,
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            strings.message(navigation.errorMessage!),
                            style: TextStyle(color: colors.onErrorContainer),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                    Row(
                      children: [
                        if (iconAsset != null) ...[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(18),
                            child: Image.asset(
                              iconAsset!,
                              width: 68,
                              height: 68,
                              errorBuilder: (_, _, _) => Icon(
                                Icons.auto_stories_rounded,
                                size: 52,
                                color: colors.primary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                        ],
                        Expanded(
                          child: Text(
                            strings.eyebrow,
                            style: TextStyle(
                              color: colors.primary,
                              fontWeight: FontWeight.w600,
                              letterSpacing: .6,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Text(
                      strings.headline,
                      style: Theme.of(context).textTheme.headlineLarge
                          ?.copyWith(fontWeight: FontWeight.w700, height: 1.22),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      strings.subtitle,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: colors.onSurfaceVariant,
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: 32),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final wide = constraints.maxWidth >= 800;
                        final cards = [
                          for (final section in [
                            AppSection.study,
                            AppSection.quiz,
                            AppSection.player,
                          ])
                            _EntryCard(
                              section: section,
                              phonePlayback: phonePlayback,
                              horizontal: !wide,
                              onTap: navigation.isSwitching
                                  ? null
                                  : () => navigation.navigate(section),
                            ),
                        ];
                        return wide
                            ? IntrinsicHeight(
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    for (var i = 0; i < cards.length; i++) ...[
                                      if (i > 0) const SizedBox(width: 20),
                                      Expanded(child: cards[i]),
                                    ],
                                  ],
                                ),
                              )
                            : Column(
                                children: [
                                  for (var i = 0; i < cards.length; i++) ...[
                                    if (i > 0) const SizedBox(height: 16),
                                    cards[i],
                                  ],
                                ],
                              );
                      },
                    ),
                    const SizedBox(height: 32),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.folder_open_outlined,
                          size: 18,
                          color: colors.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            strings.resources,
                            style: TextStyle(
                              color: colors.onSurfaceVariant,
                              fontSize: 13,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({
    required this.section,
    required this.horizontal,
    required this.phonePlayback,
    required this.onTap,
  });
  final AppSection section;
  final bool horizontal;
  final bool phonePlayback;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final strings = NavigationStrings(context);
    final number = switch (section) {
      AppSection.study => '01',
      AppSection.quiz => '02',
      AppSection.player => '03',
      _ => '',
    };
    final icon = Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        color: section == AppSection.quiz
            ? const Color(0xffb38a30).withValues(alpha: .13)
            : colors.primary.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(
        sectionIcon(section),
        color: section == AppSection.quiz
            ? const Color(0xffa77c24)
            : colors.primary,
        size: 28,
      ),
    );
    final title = Text(
      strings.label(section),
      style: Theme.of(context).textTheme.titleLarge
          ?.copyWith(fontWeight: FontWeight.w700),
    );
    final description = Text(
      section == AppSection.player && phonePlayback
          ? strings.phonePlayerDescription
          : strings.description(section),
      style: TextStyle(color: colors.onSurfaceVariant, height: 1.55),
    );
    return Material(
      color: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: colors.outlineVariant.withValues(alpha: .7)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('home-entry-${section.name}'),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: horizontal
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    icon,
                    const SizedBox(width: 18),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          title,
                          const SizedBox(height: 8),
                          description,
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.arrow_forward_rounded,
                      color: colors.primary,
                      size: 20,
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        icon,
                        Text(
                          number,
                          style: TextStyle(
                            color: colors.outline,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 26),
                    title,
                    const SizedBox(height: 10),
                    description,
                    const Spacer(),
                    const SizedBox(height: 24),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Icon(
                        Icons.arrow_forward_rounded,
                        color: colors.primary,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
