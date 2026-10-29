import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_info_gateway.dart';
import 'support_strings.dart';

Future<void> showImportHelp(BuildContext context) =>
    Navigator.of(context)
        .push<void>(MaterialPageRoute(builder: (_) => const ImportHelpPage()));

Future<void> showAppAbout(BuildContext context) =>
    Navigator.of(context)
        .push<void>(MaterialPageRoute(builder: (_) => const AppAboutPage()));

class ImportHelpPage extends StatelessWidget {
  const ImportHelpPage({super.key, this.gateway = const AppInfoGateway()});

  final AppInfoGateway gateway;

  @override
  Widget build(BuildContext context) {
    final strings = SupportStrings(context);
    final steps = strings.importSteps;
    return _SupportFrame(
      title: strings.importHelp,
      children: [
        Text(
          strings.introduction,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 24),
        _SupportCard(
          title: strings.steps,
          child: Column(
            children: [
              for (var i = 0; i < steps.length; i++)
                Padding(
                  padding: EdgeInsets.only(top: i == 0 ? 0 : 16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${i + 1}.',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Text(steps[i])),
                    ],
                  ),
                ),
            ],
          ),
        ),
        _SupportCard(
          title: strings.studyZip,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(strings.studyDescription),
              const SizedBox(height: 16),
              const _FileList([
                'manifest.json',
                'lessons.json',
                'entries.json',
              ]),
              const SizedBox(height: 16),
              Text(strings.studyAudio),
              const SizedBox(height: 12),
              Text(strings.studyLimits),
              const SizedBox(height: 8),
              _SupportLink(
                key: const ValueKey('study-format-link'),
                title: strings.studyFormat,
                uri: AppSupportLinks.studyFormat,
                gateway: gateway,
              ),
            ],
          ),
        ),
        _SupportCard(
          title: strings.quizZip,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(strings.quizDescription),
              const SizedBox(height: 16),
              const _FileList(['manifest.json', 'questions.json']),
              const SizedBox(height: 16),
              Text(strings.quizAnswers),
              const SizedBox(height: 12),
              Text(strings.quizLimits),
              const SizedBox(height: 8),
              _SupportLink(
                key: const ValueKey('quiz-format-link'),
                title: strings.quizFormat,
                uri: AppSupportLinks.quizFormat,
                gateway: gateway,
              ),
            ],
          ),
        ),
        _SupportCard(
          title: strings.troubleshooting,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                strings.unsupportedTitle,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Text(strings.unsupportedBody),
              const SizedBox(height: 20),
              Text(
                strings.updatesTitle,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Text(strings.updatesBody),
              const SizedBox(height: 16),
              Text(strings.formatHint),
            ],
          ),
        ),
        Text(
          strings.ownResources,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class AppAboutPage extends StatefulWidget {
  const AppAboutPage({super.key, this.gateway = const AppInfoGateway()});

  final AppInfoGateway gateway;

  @override
  State<AppAboutPage> createState() => _AppAboutPageState();
}

class _AppAboutPageState extends State<AppAboutPage> {
  late final Future<AppBuildInfo?> _build;

  @override
  void initState() {
    super.initState();
    _build = widget.gateway.getInfo();
  }

  @override
  Widget build(BuildContext context) {
    final strings = SupportStrings(context);
    return _SupportFrame(
      title: strings.about,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.asset(
              'assets/branding/goodgoodstudy-icon.png',
              width: 72,
              height: 72,
              excludeFromSemantics: true,
              errorBuilder: (_, _, _) =>
                  const Icon(Icons.menu_book_rounded, size: 72),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text('GoodGoodStudy', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(strings.summary),
        const SizedBox(height: 8),
        FutureBuilder<AppBuildInfo?>(
          future: _build,
          builder: (context, snapshot) {
            final info = snapshot.data;
            return Text(
              info != null
                  ? strings.version(info.version, info.buildNumber)
                  : snapshot.connectionState == ConnectionState.done
                  ? strings.versionUnavailable
                  : strings.loadingVersion,
              key: const ValueKey('installed-app-version'),
            );
          },
        ),
        const SizedBox(height: 24),
        Card(
          margin: const EdgeInsets.only(bottom: 20),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              children: [
                _SupportLink(
                  key: const ValueKey('source-code-link'),
                  title: strings.source,
                  uri: AppSupportLinks.source,
                  gateway: widget.gateway,
                ),
                _SupportLink(
                  key: const ValueKey('software-license-link'),
                  title: strings.license,
                  uri: AppSupportLinks.license,
                  gateway: widget.gateway,
                ),
                _SupportLink(
                  key: const ValueKey('third-party-notices-link'),
                  title: strings.thirdPartyNotices,
                  uri: AppSupportLinks.notices,
                  gateway: widget.gateway,
                ),
                _SupportLink(
                  key: const ValueKey('privacy-policy-link'),
                  title: strings.privacy,
                  uri: AppSupportLinks.privacy,
                  gateway: widget.gateway,
                ),
                ListTile(
                  key: const ValueKey('component-licenses'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(strings.componentLicenses),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) =>
                          const LicensePage(applicationName: 'GoodGoodStudy'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Text(strings.licenseSummary),
        const SizedBox(height: 16),
        Text(
          strings.ownResources,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _SupportFrame extends StatelessWidget {
  const _SupportFrame({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
    ),
    body: SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
      ),
    ),
  );
}

class _SupportCard extends StatelessWidget {
  const _SupportCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 20),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          child,
        ],
      ),
    ),
  );
}

class _FileList extends StatelessWidget {
  const _FileList(this.files);

  final List<String> files;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final file in files)
            Text(file, style: const TextStyle(fontFamily: 'monospace')),
        ],
      ),
    ),
  );
}

class _SupportLink extends StatefulWidget {
  const _SupportLink({
    super.key,
    required this.title,
    required this.uri,
    required this.gateway,
  });

  final String title;
  final Uri uri;
  final AppInfoGateway gateway;

  @override
  State<_SupportLink> createState() => _SupportLinkState();
}

class _SupportLinkState extends State<_SupportLink> {
  bool _opening = false;

  Future<void> _open() async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final opened = await widget.gateway.openLink(widget.uri);
      if (!mounted || opened) return;
      final route = DialogRoute<bool>(
        context: context,
        builder: (dialogContext) {
          final strings = SupportStrings(dialogContext);
          return AlertDialog(
            title: Text(strings.cannotOpenLink),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(strings.openLinkHint),
                  const SizedBox(height: 12),
                  SelectableText(widget.uri.toString()),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(strings.close),
              ),
              FilledButton(
                onPressed: () async {
                  try {
                    await Clipboard.setData(
                      ClipboardData(text: widget.uri.toString()),
                    );
                    if (dialogContext.mounted) {
                      Navigator.of(dialogContext).pop(true);
                    }
                  } on Object {
                    if (dialogContext.mounted) {
                      Navigator.of(dialogContext).pop(false);
                    }
                  }
                },
                child: Text(strings.copyLink),
              ),
            ],
          );
        },
      );
      final copied = await Navigator.of(context).push<bool>(route);
      await route.completed;
      if (mounted && copied != null) {
        final strings = SupportStrings(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(copied ? strings.copied : strings.cannotCopy)),
        );
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(widget.title),
    trailing: const Icon(Icons.open_in_new_rounded, size: 20),
    onTap: _opening ? null : _open,
  );
}
