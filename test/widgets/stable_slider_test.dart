import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_player/widgets/stable_slider.dart';

void main() {
  final binding = RecordingSemanticsBinding();

  testWidgets(
    'route and dialog keep incremental slider semantics connected during drag and menu dismissal',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        binding.recorder.reset();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => Column(
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const Scaffold(
                            body: Center(child: _SliderControls()),
                          ),
                        ),
                      ),
                      child: const Text('Push route'),
                    ),
                    TextButton(
                      onPressed: () => showDialog<void>(
                        context: context,
                        builder: (_) =>
                            const AlertDialog(content: _SliderControls()),
                      ),
                      child: const Text('Open dialog'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        for (final entry in ['Push route', 'Open dialog']) {
          await tester.tap(find.text(entry));
          await tester.pumpAndSettle();
          final slider = find.byType(Slider);
          final owner = tester
              .element(slider)
              .findRenderObject()!
              .owner!
              .semanticsOwner!;
          final node = _findSlider(owner.rootSemanticsNode!)!;
          final data = node.getSemanticsData();
          expect(data.flagsCollection.isSlider, isTrue);
          expect(data.hasAction(ui.SemanticsAction.increase), isTrue);
          expect(data.hasAction(ui.SemanticsAction.decrease), isTrue);
          final before = tester
              .widget<StableSlider>(find.byType(StableSlider))
              .value;
          owner.performAction(node.id, ui.SemanticsAction.increase);
          await tester.pumpAndSettle();
          expect(
            tester.widget<StableSlider>(find.byType(StableSlider)).value,
            greaterThan(before),
          );
          final gesture = await tester.startGesture(tester.getCenter(slider));
          await gesture.moveBy(const Offset(45, 0));
          await tester.pump(const Duration(milliseconds: 300));
          expect(binding.recorder.orphans, isEmpty);
          await gesture.up();
          await tester.pumpAndSettle();
          await tester.tap(find.byType(DropdownButton<int>));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Two').last);
          await tester.pumpAndSettle();
          expect(find.text('Choice: 2'), findsOneWidget);
          await tester.tap(find.text('Close'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(binding.recorder.orphans, isEmpty);
        }
        expect(binding.recorder.commits, greaterThan(10));
        expect(binding.recorder.incrementalCommits, greaterThan(0));
      } finally {
        semantics.dispose();
      }
    },
  );
}

SemanticsNode? _findSlider(SemanticsNode node) {
  if (node.flagsCollection.isSlider) return node;
  SemanticsNode? result;
  node.visitChildren((child) {
    result ??= _findSlider(child);
    return result == null;
  });
  return result;
}

class _SliderControls extends StatefulWidget {
  const _SliderControls();

  @override
  State<_SliderControls> createState() => _SliderControlsState();
}

class _SliderControlsState extends State<_SliderControls> {
  double value = 0.3;
  int choice = 1;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 300,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        StableSlider(
          value: value,
          divisions: 10,
          label: '${(value * 100).round()}',
          showValueIndicator: ShowValueIndicator.onDrag,
          semanticFormatterCallback: (value) =>
              '${(value * 100).round()} percent',
          onChanged: (next) => setState(() => value = next),
        ),
        DropdownButton<int>(
          value: choice,
          items: const [
            DropdownMenuItem(value: 1, child: Text('One')),
            DropdownMenuItem(value: 2, child: Text('Two')),
          ],
          onChanged: (next) => setState(() => choice = next!),
        ),
        Text('Choice: $choice'),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

class RecordingSemanticsBinding extends AutomatedTestWidgetsFlutterBinding {
  final recorder = _IncrementalSemanticsRecorder();

  @override
  ui.SemanticsUpdateBuilder createSemanticsUpdateBuilder() =>
      _RecordingUpdateBuilder(super.createSemanticsUpdateBuilder(), recorder);
}

class _IncrementalSemanticsRecorder {
  final Map<int, List<int>> children = {};
  final List<int> orphans = [];
  int commits = 0;
  int incrementalCommits = 0;

  void reset() {
    children.clear();
    orphans.clear();
    commits = 0;
    incrementalCommits = 0;
  }

  void record(Map<int, List<int>> delta) {
    commits++;
    if (!delta.containsKey(0)) incrementalCommits++;
    children.addAll(delta);
    final reachable = <int>{};
    final pending = <int>[0];
    while (pending.isNotEmpty) {
      final id = pending.removeLast();
      if (reachable.add(id)) pending.addAll(children[id] ?? const []);
    }
    orphans.addAll(delta.keys.where((id) => !reachable.contains(id)));
    children.removeWhere((id, _) => !reachable.contains(id));
  }
}

class _RecordingUpdateBuilder implements ui.SemanticsUpdateBuilder {
  _RecordingUpdateBuilder(this.delegate, this.recorder);

  final ui.SemanticsUpdateBuilder delegate;
  final _IncrementalSemanticsRecorder recorder;
  final Map<int, List<int>> delta = {};

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #updateNode) {
      final arguments = invocation.namedArguments;
      delta[arguments[#id] as int] = List<int>.of(
        arguments[#childrenInTraversalOrder] as List<int>,
      );
      Function.apply(delegate.updateNode, [], arguments);
      return null;
    }
    return super.noSuchMethod(invocation);
  }

  @override
  void updateCustomAction({
    required int id,
    String? label,
    String? hint,
    int overrideId = -1,
  }) => delegate.updateCustomAction(
    id: id,
    label: label,
    hint: hint,
    overrideId: overrideId,
  );

  @override
  ui.SemanticsUpdate build() {
    recorder.record(delta);
    return delegate.build();
  }
}
