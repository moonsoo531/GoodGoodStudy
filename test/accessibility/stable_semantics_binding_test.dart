import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_player/accessibility/stable_semantics_binding.dart';
import 'package:offline_player/widgets/stable_slider.dart';

void main() {
  final binding = _StableTestBinding();

  test('a portal-only first update cannot become the native root', () {
    final bridge = _NativeBridgeModel();
    expect(() => bridge.commit({7: _fields(7)}), returnsNormally);
    expect(
      () => bridge.commit({
        0: _fields(0, children: [7]),
      }),
      throwsStateError,
      reason: 'An unfiltered orphan becomes the bridge root and has no parent.',
    );

    final cache = StableSemanticsUpdateCache();
    final first = _RecordingBuilder();
    final builder = cache.wrap(first);
    _node(builder, _fields(7, label: '播放'));
    builder.build().dispose();
    expect(first.nodes, isEmpty);

    final second = _RecordingBuilder();
    final attached = cache.wrap(second);
    _node(attached, _fields(0, children: [7]));
    attached.build().dispose();
    expect(second.nodes.keys, orderedEquals([0, 7]));
    expect(second.nodes[7]![#label], '播放');
    expect(() => _NativeBridgeModel().commit(second.nodes), returnsNormally);
  });

  test(
    'orphan descendants stay out of an otherwise complete rooted update',
    () {
      final cache = StableSemanticsUpdateCache();
      final output = _RecordingBuilder();
      final builder = cache.wrap(output);
      _node(builder, _fields(0, children: [1]));
      _node(builder, _fields(1, label: '音量'));
      _node(builder, _fields(8, children: [9]));
      _node(builder, _fields(9, label: '隐藏浮层'));
      builder.build().dispose();
      expect(output.nodes.keys, orderedEquals([0, 1]));
      expect(cache.cachedNodeIds, {0, 1, 8, 9});
    },
  );

  test('moving a cached subtree resends the child and all descendants', () {
    final cache = StableSemanticsUpdateCache();
    final bridge = _NativeBridgeModel();
    final initial = _emit(cache, {
      0: _fields(0, children: [1, 2]),
      1: _fields(1, children: [3]),
      2: _fields(2),
      3: _fields(3, children: [4]),
      4: _fields(4, label: '视频字幕'),
    });
    bridge.commit(initial.nodes);
    final delta = {
      1: _fields(1),
      2: _fields(2, children: [3]),
    };
    expect(() => bridge.commit(delta), throwsStateError);

    final moved = _emit(cache, delta);
    expect(moved.nodes.keys.toSet(), {0, 1, 2, 3, 4});
    expect(moved.nodes[3]![#childrenInTraversalOrder], [4]);
    expect(moved.nodes[4]![#label], '视频字幕');
    expect(() => bridge.commit(moved.nodes), returnsNormally);
  });

  test('a new parent claim removes a stale cached old-parent edge', () {
    final cache = StableSemanticsUpdateCache();
    _emit(cache, {
      0: _fields(0, children: [1, 2]),
      1: _fields(1, children: [3]),
      2: _fields(2),
      3: _fields(3),
    });
    final moved = _emit(cache, {
      2: _fields(2, children: [3]),
    });
    expect(moved.nodes[1]![#childrenInTraversalOrder], isEmpty);
    expect(moved.nodes[2]![#childrenInTraversalOrder], [3]);
  });

  test('same-frame portal parents follow their owner regardless of order', () {
    for (final reverse in [false, true]) {
      final cache = StableSemanticsUpdateCache();
      final entries = <int, Map<Symbol, dynamic>>{
        0: _fields(0, children: [1, 2]),
        1: _fields(1, children: [3]),
        2: _fields(2, children: [3, 3]),
        3: _fields(3, children: [4], label: '播放'),
        4: _fields(4, label: '字幕'),
      }.entries.toList();
      final output = _emit(
        cache,
        Map.fromEntries(reverse ? entries.reversed : entries),
        traversalParents: {3: 2},
      );
      expect(output.nodes.keys.toSet(), {0, 1, 2, 3, 4});
      expect(output.nodes[1]![#childrenInTraversalOrder], isEmpty);
      expect(output.nodes[2]![#childrenInTraversalOrder], [3]);
      expect(output.nodes[1]![#childrenInHitTestOrder], [3]);
      expect(output.nodes[3]![#label], '播放');
      expect(output.nodes[4]![#label], '字幕');
      expect(() => _NativeBridgeModel().commit(output.nodes), returnsNormally);
    }
  });

  test('authoritative reparent resends descendants and overrides recency', () {
    final cache = StableSemanticsUpdateCache();
    final bridge = _NativeBridgeModel();
    bridge.commit(
      _emit(cache, {
        0: _fields(0, children: [1, 2]),
        1: _fields(1, children: [3]),
        2: _fields(2),
        3: _fields(3, children: [4]),
        4: _fields(4, label: '音量'),
      }).nodes,
    );
    final moved = _emit(
      cache,
      {
        1: _fields(1, children: [3]),
        2: _fields(2, children: [3]),
      },
      traversalParents: {3: 2},
    );
    expect(moved.nodes[1]![#childrenInTraversalOrder], isEmpty);
    expect(moved.nodes[2]![#childrenInTraversalOrder], [3]);
    expect(moved.nodes[4]![#label], '音量');
    bridge.commit(moved.nodes);

    final staleNewClaim = _emit(
      cache,
      {
        1: _fields(1, children: [3]),
      },
      traversalParents: {3: 2},
    );
    expect(staleNewClaim.nodes[1]![#childrenInTraversalOrder], isEmpty);
    expect(staleNewClaim.nodes[2]![#childrenInTraversalOrder], [3]);
    expect(() => bridge.commit(staleNewClaim.nodes), returnsNormally);
  });

  test('ambiguous or inconsistent parents never choose an arbitrary edge', () {
    final delta = {
      0: _fields(0, children: [1, 2]),
      1: _fields(1, children: [3]),
      2: _fields(2, children: [3]),
      3: _fields(3),
    };
    expect(() => _emit(StableSemanticsUpdateCache(), delta), throwsStateError);
    expect(
      () =>
          _emit(StableSemanticsUpdateCache(), delta, traversalParents: {3: 99}),
      throwsStateError,
    );
  });

  test(
    'removed nodes disappear from output and disposed nodes leave cache',
    () {
      final cache = StableSemanticsUpdateCache();
      _emit(cache, {
        0: _fields(0, children: [1]),
        1: _fields(1, children: [2]),
        2: _fields(2),
      });
      final removed = _emit(cache, {0: _fields(0)}, alive: {0});
      expect(removed.nodes.keys, [0]);
      expect(cache.cachedNodeIds, {0});
    },
  );

  test(
    'all SDK fields survive caching, including attributed text and actions',
    () {
      final cache = StableSemanticsUpdateCache();
      final first = _RecordingBuilder();
      final builder = cache.wrap(first);
      final expected = _fields(0, children: [1]);
      expected.addAll({
        #flags: ui.SemanticsFlags(
          isSlider: true,
          isEnabled: ui.Tristate.isTrue,
        ),
        #actions:
            ui.SemanticsAction.increase.index |
            ui.SemanticsAction.decrease.index,
        #label: '播放进度',
        #labelAttributes: <ui.StringAttribute>[
          ui.LocaleStringAttribute(
            range: const ui.TextRange(start: 0, end: 4),
            locale: const ui.Locale('zh'),
          ),
        ],
        #value: '12秒',
        #increasedValue: '17秒',
        #decreasedValue: '7秒',
        #hint: '调节播放位置',
        #tooltip: '播放进度',
        #textSelectionBase: 1,
        #textSelectionExtent: 2,
        #maxValueLength: 10,
        #currentValueLength: 3,
        #scrollChildren: 20,
        #scrollIndex: 4,
        #scrollPosition: 10.5,
        #scrollExtentMin: -2.0,
        #scrollExtentMax: 99.0,
        #rect: const ui.Rect.fromLTWH(1, 2, 30, 40),
        #identifier: 'playback-progress',
        #textDirection: ui.TextDirection.rtl,
        #additionalActions: Int32List.fromList([91]),
        #headingLevel: 2,
        #linkUrl: 'local-media:lesson',
        #role: ui.SemanticsRole.tab,
        #controlsNodes: <String>['video'],
        #validationResult: ui.SemanticsValidationResult.valid,
        #hitTestBehavior: ui.SemanticsHitTestBehavior.opaque,
        #inputType: ui.SemanticsInputType.text,
        #locale: const ui.Locale('ja', 'JP'),
        #minValue: '0',
        #maxValue: '100',
      });
      _node(builder, expected);
      _node(builder, _fields(1, label: '下一项'));
      builder.updateCustomAction(id: 91, label: '跳至开头', hint: '重播本视频');
      builder.build().dispose();
      expect(first.nodes[0], equals(expected));

      final unchanged = _emit(cache, {1: _fields(1, label: '下一集')});
      expect(unchanged.nodes[0], equals(expected));
      expect(unchanged.actions[91], {
        #id: 91,
        #label: '跳至开头',
        #hint: '重播本视频',
        #overrideId: -1,
      });
    },
  );

  test('typed buffers are copied before a later framework mutation', () {
    final cache = StableSemanticsUpdateCache();
    final fields = _fields(0, children: [1]);
    _emit(cache, {0: fields, 1: _fields(1)});
    (fields[#transform] as Float64List)[12] = 500;
    (fields[#hitTestTransform] as Float64List)[13] = 600;
    (fields[#childrenInTraversalOrder] as Int32List)[0] = 99;
    final output = _emit(cache, {1: _fields(1, label: '暂停')});
    expect((output.nodes[0]![#transform] as Float64List)[12], 0);
    expect((output.nodes[0]![#hitTestTransform] as Float64List)[13], 0);
    expect(output.nodes[0]![#childrenInTraversalOrder], [1]);
  });

  test('resetting cache discards an old owner and its custom actions', () {
    final cache = StableSemanticsUpdateCache();
    final output = _RecordingBuilder();
    final builder = cache.wrap(output);
    _node(builder, _fields(0, children: [1]));
    _node(builder, _fields(1));
    builder.updateCustomAction(id: 9, label: '旧动作');
    builder.build().dispose();
    cache.clear();
    final reset = _emit(cache, {0: _fields(0)});
    expect(reset.nodes.keys, [0]);
    expect(reset.actions, isEmpty);
    expect(cache.cachedNodeIds, {0});
  });

  test('invalid attached topology is reported before reaching native code', () {
    final cache = StableSemanticsUpdateCache();
    expect(
      () => _emit(cache, {
        0: _fields(0, children: [99]),
      }),
      throwsA(
        isA<StateError>().having((e) => e.message, 'message', contains('99')),
      ),
    );
    cache.clear();
    expect(
      () => _emit(cache, {
        0: _fields(0, children: [1]),
        1: _fields(1, children: [0]),
      }),
      throwsStateError,
    );
  });

  testWidgets(
    'nested portal traversal parents publish a complete accessible cold start',
    (tester) async {
      final semantics = tester.ensureSemantics();
      binding.commits.clear();
      var taps = 0;
      try {
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Semantics(
              container: true,
              explicitChildNodes: true,
              label: 'Outer portal',
              traversalParentIdentifier: 'outer',
              child: Semantics(
                container: true,
                explicitChildNodes: true,
                label: 'Inner portal',
                traversalParentIdentifier: 'inner',
                child: Semantics(
                  container: true,
                  explicitChildNodes: true,
                  label: '播放',
                  button: true,
                  onTap: () => taps++,
                  traversalChildIdentifier: 'outer',
                  child: Semantics(
                    container: true,
                    label: '日本語字幕',
                    child: const SizedBox(width: 100, height: 40),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final output = binding.commits.last;
        int nodeId(String label) => output.entries
            .singleWhere((entry) => entry.value[#label] == label)
            .key;
        final outer = nodeId('Outer portal');
        final inner = nodeId('Inner portal');
        final button = nodeId('播放');
        expect(output[outer]![#childrenInTraversalOrder], contains(button));
        expect(
          output[inner]![#childrenInTraversalOrder],
          isNot(contains(button)),
        );
        expect(output[inner]![#childrenInHitTestOrder], contains(button));
        expect(output.values.any((node) => node[#label] == '日本語字幕'), isTrue);
        final owner = tester
            .renderObject(find.byType(Semantics).first)
            .owner!
            .semanticsOwner!;
        expect(owner.getSemanticsNode(button)!.parent!.id, inner);
        expect(owner.getSemanticsNode(button)!.traversalParent!.id, outer);
        owner.performAction(button, ui.SemanticsAction.tap);
        expect(taps, 1);
        final bridge = _NativeBridgeModel();
        for (final commit in binding.commits) {
          bridge.commit(commit);
        }
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'portal sliders remain accessible across panel/fullscreen/route changes',
    (tester) async {
      final semantics = tester.ensureSemantics();
      binding.commits.clear();
      try {
        await tester.pumpWidget(const MaterialApp(home: _PlayerHarness()));
        await tester.pumpAndSettle();
        final slider = _sliderNode(tester);
        expect(slider, isNotNull);
        final owner = tester
            .renderObject(find.byType(Slider).first)
            .owner!
            .semanticsOwner!;
        expect(
          slider!.getSemanticsData().hasAction(ui.SemanticsAction.increase),
          isTrue,
        );
        owner.performAction(slider.id, ui.SemanticsAction.increase);
        await tester.pumpAndSettle();
        expect(find.text('Position 1'), findsOneWidget);

        for (var cycle = 0; cycle < 3; cycle++) {
          await tester.tap(find.text('字幕'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Full screen'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Exit full screen'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('播放列表'));
          await tester.pumpAndSettle();
        }
        await tester.tap(find.text('Settings'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        final bridge = _NativeBridgeModel();
        for (final commit in binding.commits) {
          bridge.commit(commit);
        }
        expect(binding.commits.length, greaterThan(10));
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        semantics.dispose();
      }
    },
  );
}

_RecordingBuilder _emit(
  StableSemanticsUpdateCache cache,
  Map<int, Map<Symbol, dynamic>> delta, {
  Set<int>? alive,
  Map<int, int>? traversalParents,
}) {
  final output = _RecordingBuilder();
  final builder = cache.wrap(
    output,
    isNodeAlive: alive?.contains,
    resolveTraversalParent: traversalParents == null
        ? null
        : (id, _) => traversalParents[id],
  );
  for (final fields in delta.values) {
    _node(builder, fields);
  }
  builder.build().dispose();
  return output;
}

void _node(ui.SemanticsUpdateBuilder builder, Map<Symbol, dynamic> fields) {
  Function.apply(builder.updateNode, const [], fields);
}

Map<Symbol, dynamic> _fields(
  int id, {
  List<int> children = const [],
  String label = '',
}) => {
  #id: id,
  #flags: ui.SemanticsFlags.none,
  #actions: 0,
  #maxValueLength: -1,
  #currentValueLength: -1,
  #textSelectionBase: -1,
  #textSelectionExtent: -1,
  #platformViewId: -1,
  #scrollChildren: 0,
  #scrollIndex: 0,
  #traversalParent: -1,
  #scrollPosition: 0.0,
  #scrollExtentMax: 0.0,
  #scrollExtentMin: 0.0,
  #rect: const ui.Rect.fromLTWH(0, 0, 100, 40),
  #identifier: '',
  #label: label,
  #labelAttributes: <ui.StringAttribute>[],
  #value: '',
  #valueAttributes: <ui.StringAttribute>[],
  #increasedValue: '',
  #increasedValueAttributes: <ui.StringAttribute>[],
  #decreasedValue: '',
  #decreasedValueAttributes: <ui.StringAttribute>[],
  #hint: '',
  #hintAttributes: <ui.StringAttribute>[],
  #tooltip: '',
  #textDirection: ui.TextDirection.ltr,
  #transform: Float64List.fromList([
    1,
    0,
    0,
    0,
    0,
    1,
    0,
    0,
    0,
    0,
    1,
    0,
    0,
    0,
    0,
    1,
  ]),
  #hitTestTransform: Float64List.fromList([
    1,
    0,
    0,
    0,
    0,
    1,
    0,
    0,
    0,
    0,
    1,
    0,
    0,
    0,
    0,
    1,
  ]),
  #childrenInTraversalOrder: Int32List.fromList(children),
  #childrenInHitTestOrder: Int32List.fromList(children.reversed.toList()),
  #additionalActions: Int32List(0),
  #headingLevel: 0,
  #linkUrl: '',
  #role: ui.SemanticsRole.none,
  #controlsNodes: null,
  #validationResult: ui.SemanticsValidationResult.none,
  #hitTestBehavior: ui.SemanticsHitTestBehavior.defer,
  #inputType: ui.SemanticsInputType.none,
  #locale: null,
  #minValue: '',
  #maxValue: '',
};

class _RecordingBuilder implements ui.SemanticsUpdateBuilder {
  final Map<int, Map<Symbol, dynamic>> nodes = {};
  final Map<int, Map<Symbol, dynamic>> actions = {};

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #updateNode) {
      nodes[invocation.namedArguments[#id] as int] = Map.of(
        invocation.namedArguments,
      );
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
  }) {
    actions[id] = {
      #id: id,
      #label: label,
      #hint: hint,
      #overrideId: overrideId,
    };
  }

  @override
  ui.SemanticsUpdate build() => ui.SemanticsUpdateBuilder().build();
}

/// Models the native bridge requirements relevant to the crash stack.
class _NativeBridgeModel {
  int? root;
  Map<int, Map<Symbol, dynamic>> _tree = {};
  Map<int, int> _parents = {};

  void commit(Map<int, Map<Symbol, dynamic>> delta) {
    if (delta.isEmpty) return;
    for (final entry in delta.entries) {
      for (final child in entry.value[#childrenInTraversalOrder] as Int32List) {
        if (!_tree.containsKey(child)) continue;
        final oldParent = _parents[child];
        if (oldParent == null) {
          throw StateError('Reparenting the native root $child');
        }
        if (oldParent != entry.key) {
          void requireSubtree(int id) {
            if (!delta.containsKey(id)) {
              throw StateError('Moved subtree omitted node $id');
            }
            for (final child
                in _tree[id]?[#childrenInTraversalOrder] as Int32List? ??
                    Int32List(0)) {
              requireSubtree(child);
            }
          }

          requireSubtree(child);
        }
      }
    }
    final merged = {..._tree, ...delta};
    root ??= delta.containsKey(0) ? 0 : delta.keys.first;
    final retained = <int, Map<Symbol, dynamic>>{};
    final parents = <int, int>{};
    void visit(int id) {
      if (retained.containsKey(id)) {
        throw StateError('Duplicate node or cycle: $id');
      }
      final fields = merged[id];
      if (fields == null) throw StateError('Missing node $id');
      retained[id] = fields;
      for (final child in fields[#childrenInTraversalOrder] as Int32List) {
        parents[child] = id;
        visit(child);
      }
    }

    visit(root!);
    _tree = retained;
    _parents = parents;
  }
}

class _RecordingTestBase extends AutomatedTestWidgetsFlutterBinding {
  final List<Map<int, Map<Symbol, dynamic>>> commits = [];

  @override
  ui.SemanticsUpdateBuilder createSemanticsUpdateBuilder() =>
      _RecordingNativeBuilder(super.createSemanticsUpdateBuilder(), commits);
}

class _StableTestBinding extends _RecordingTestBase
    with StableSemanticsUpdates {
  @override
  bool get usesStableSemantics => true;
}

class _RecordingNativeBuilder extends _RecordingBuilder {
  _RecordingNativeBuilder(this.delegate, this.commits);
  final ui.SemanticsUpdateBuilder delegate;
  final List<Map<int, Map<Symbol, dynamic>>> commits;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #updateNode) {
      super.noSuchMethod(invocation);
      Function.apply(delegate.updateNode, const [], invocation.namedArguments);
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
  }) {
    super.updateCustomAction(
      id: id,
      label: label,
      hint: hint,
      overrideId: overrideId,
    );
    delegate.updateCustomAction(
      id: id,
      label: label,
      hint: hint,
      overrideId: overrideId,
    );
  }

  @override
  ui.SemanticsUpdate build() {
    commits.add(Map.of(nodes));
    return delegate.build();
  }
}

SemanticsNode? _sliderNode(WidgetTester tester) {
  final owner = tester
      .renderObject(find.byType(Slider).first)
      .owner!
      .semanticsOwner!;
  SemanticsNode? result;
  void findNode(SemanticsNode node) {
    if (node.flagsCollection.isSlider) result ??= node;
    node.visitChildren((child) {
      findNode(child);
      return true;
    });
  }

  findNode(owner.rootSemanticsNode!);
  return result;
}

class _PlayerHarness extends StatefulWidget {
  const _PlayerHarness();
  @override
  State<_PlayerHarness> createState() => _PlayerHarnessState();
}

class _PlayerHarnessState extends State<_PlayerHarness> {
  bool fullScreen = false;
  bool subtitles = false;
  double position = 0;

  @override
  Widget build(BuildContext context) => Scaffold(
    key: ValueKey(fullScreen),
    appBar: fullScreen ? null : AppBar(title: const Text('播放器')),
    body: Column(
      children: [
        if (!fullScreen)
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('播放列表')),
              ButtonSegment(value: true, label: Text('字幕')),
            ],
            selected: {subtitles},
            onSelectionChanged: (value) =>
                setState(() => subtitles = value.single),
          ),
        Expanded(
          child: Row(
            children: [
              const Expanded(child: ColoredBox(color: Colors.black)),
              if (!fullScreen)
                SizedBox(
                  width: 200,
                  child: subtitles
                      ? ListView(
                          children: const [
                            Text('日本語字幕'),
                            Tooltip(
                              message: '隐藏',
                              child: Icon(Icons.visibility),
                            ),
                          ],
                        )
                      : ListView(children: const [Text('第2课'), Text('第10课')]),
                ),
            ],
          ),
        ),
        StableSlider(
          value: position,
          max: 10,
          divisions: 10,
          onChanged: (value) => setState(() => position = value),
        ),
        Text('Position ${position.round()}'),
        TextButton(
          onPressed: () => setState(() => fullScreen = !fullScreen),
          child: Text(fullScreen ? 'Exit full screen' : 'Full screen'),
        ),
        TextButton(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
              content: StableSlider(value: .5, onChanged: (_) {}),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ],
            ),
          ),
          child: const Text('Settings'),
        ),
      ],
    ),
  );
}
