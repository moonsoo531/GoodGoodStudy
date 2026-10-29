import 'package:flutter/material.dart';

import 'resource_sync_controller.dart';
import 'sync_strings.dart';

Future<void> showSyncSettings(BuildContext context) async {
  final controller = ResourceSyncScope.maybeOf(context);
  if (controller == null) return;
  await Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => CloudSyncSettingsPage(controller: controller),
    ),
  );
}

class CloudSyncSettingsPage extends StatefulWidget {
  const CloudSyncSettingsPage({super.key, required this.controller});

  final ResourceSyncController controller;

  @override
  State<CloudSyncSettingsPage> createState() => _CloudSyncSettingsPageState();
}

class _CloudSyncSettingsPageState extends State<CloudSyncSettingsPage> {
  bool _actionBusy = false;
  bool _actionError = false;

  bool get _busy => _actionBusy || widget.controller.busy;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy || !mounted) return;
    setState(() {
      _actionBusy = true;
      _actionError = false;
    });
    try {
      await action();
    } on Object {
      if (mounted) setState(() => _actionError = true);
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  Future<bool> _confirm({
    required String title,
    required String body,
    required String accept,
  }) async {
    final route = DialogRoute<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(child: Text(body)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(SyncStrings(dialogContext).cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(accept),
          ),
        ],
      ),
    );
    final accepted = await Navigator.of(context).push<bool>(route);
    await route.completed;
    return mounted && accepted == true;
  }

  Future<void> _setEnabled(bool enabled) => _run(() async {
    final strings = SyncStrings(context);
    if (enabled && widget.controller.accountChanged) {
      if (!await _confirm(
        title: strings.confirmAccountTitle,
        body: strings.confirmAccountBody,
        accept: strings.confirmAndEnable,
      )) {
        return;
      }
    }
    if (mounted) await widget.controller.setEnabled(enabled);
  });

  Future<void> _resolve(SyncConflict conflict, {required bool useRemote}) =>
      _run(() async {
        if (useRemote) {
          if (!conflict.canUseRemote) return;
          final strings = SyncStrings(context);
          if (!await _confirm(
            title: strings.confirmRemoteTitle,
            body: strings.confirmRemoteBody,
            accept: strings.useRemote,
          )) {
            return;
          }
        }
        if (!mounted) return;
        final current = widget.controller.conflicts
            .where((value) => value.id == conflict.id)
            .firstOrNull;
        if (current == null || (useRemote && !current.canUseRemote)) return;
        await widget.controller.resolveConflict(
          current.id,
          useRemote: useRemote,
        );
      });

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final controller = widget.controller;
      final strings = SyncStrings(context);
      final colors = Theme.of(context).colorScheme;
      return Scaffold(
        appBar: AppBar(title: Text(strings.title)),
        body: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _card(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.cloud_outlined,
                            size: 36,
                            color: colors.primary,
                          ),
                          const SizedBox(height: 12),
                          Text(strings.intro),
                          const SizedBox(height: 12),
                          SwitchListTile.adaptive(
                            key: const ValueKey('icloud-sync-enabled'),
                            contentPadding: EdgeInsets.zero,
                            title: Text(strings.enable),
                            subtitle: Text(strings.optIn),
                            value: controller.enabled,
                            onChanged: _busy ? null : _setEnabled,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            strings.disabling,
                            style: TextStyle(color: colors.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    if (controller.accountChanged)
                      _notice(
                        icon: Icons.account_circle_outlined,
                        text: strings.accountChanged,
                        action: OutlinedButton(
                          onPressed: _busy ? null : () => _setEnabled(true),
                          child: Text(strings.confirmAndEnable),
                        ),
                      ),
                    _card(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            strings.status,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 14),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                controller.available
                                    ? Icons.cloud_done_outlined
                                    : Icons.cloud_outlined,
                                color: colors.primary,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(strings.phase(controller.phase)),
                                    const SizedBox(height: 4),
                                    Text(
                                      strings.availability(
                                        controller.availability,
                                      ),
                                      style: TextStyle(
                                        color: colors.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          if (_busy) ...[
                            const SizedBox(height: 16),
                            const LinearProgressIndicator(),
                          ],
                          const SizedBox(height: 16),
                          Text(
                            strings.transfers(
                              controller.queuedUploads,
                              controller.pendingDownloads,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${strings.checkingTime}: ${_lastChecked(context, strings)}',
                          ),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            key: const ValueKey('icloud-sync-now'),
                            onPressed:
                                _busy ||
                                    !controller.enabled ||
                                    controller.accountChanged
                                ? null
                                : () => _run(controller.synchronize),
                            icon: const Icon(Icons.sync_rounded),
                            label: Text(strings.syncNow),
                          ),
                        ],
                      ),
                    ),
                    if (_actionError || controller.lastError != null)
                      _notice(icon: Icons.error_outline, text: strings.failure),
                    if (controller.pendingRemote)
                      _notice(
                        icon: Icons.home_outlined,
                        text: strings.pendingRemote,
                      ),
                    _card(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            strings.included,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 12),
                          _includedItem(strings.packages),
                          _includedItem(strings.packageAudio),
                          _includedItem(strings.progress),
                          const SizedBox(height: 8),
                          Text(
                            strings.excluded,
                            style: TextStyle(color: colors.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    if (controller.conflicts.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 12, 4, 12),
                        child: Text(
                          strings.conflicts,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      for (final conflict in controller.conflicts)
                        _conflictCard(conflict, strings),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );

  String _lastChecked(BuildContext context, SyncStrings strings) {
    final checked = widget.controller.lastCheckedAt;
    if (checked == null) return strings.notChecked;
    final local = checked.toLocal();
    final localizations = MaterialLocalizations.of(context);
    final date = localizations.formatMediumDate(local);
    final time = localizations.formatTimeOfDay(
      TimeOfDay.fromDateTime(local),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
    return '$date $time';
  }

  Widget _card({required Widget child}) => Card(
    margin: const EdgeInsets.only(bottom: 16),
    child: Padding(padding: const EdgeInsets.all(20), child: child),
  );

  Widget _notice({
    required IconData icon,
    required String text,
    Widget? action,
  }) => _card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(child: Text(text)),
          ],
        ),
        if (action != null) ...[const SizedBox(height: 12), action],
      ],
    ),
  );

  Widget _includedItem(String label) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.check_rounded,
          size: 20,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(label)),
      ],
    ),
  );

  Widget _conflictCard(SyncConflict conflict, SyncStrings strings) => _card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          strings.kind(conflict.kind),
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 6),
        Text(
          conflict.title.trim().isEmpty ? conflict.packageId : conflict.title,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        Text(
          conflict.kind == 'studyProgress'
              ? strings.progressConflict
              : strings.packageConflict,
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            OutlinedButton(
              key: ValueKey('icloud-keep-${conflict.id}'),
              onPressed: _busy
                  ? null
                  : () => _resolve(conflict, useRemote: false),
              child: Text(strings.keepLocal),
            ),
            if (conflict.canUseRemote)
              FilledButton(
                key: ValueKey('icloud-use-${conflict.id}'),
                onPressed: _busy
                    ? null
                    : () => _resolve(conflict, useRemote: true),
                child: Text(strings.useRemote),
              ),
          ],
        ),
      ],
    ),
  );
}
