import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Installs complete, rooted semantics updates for the app's single macOS view.
///
/// The pinned Flutter engine chooses its native accessibility root from the
/// first update. An isolated OverlayPortal descendant can otherwise become
/// that root, then crash the bridge when it is subsequently reparented. The
/// bridge also requires a moved node and all its descendants in the same
/// transaction. Complete rooted snapshots satisfy both requirements without
/// disabling semantics or changing any labels, actions, or hit-test metadata.
///
/// Construct this once in main, before any other binding is initialized.
class StableSemanticsBinding extends WidgetsFlutterBinding
    with StableSemanticsUpdates {
  StableSemanticsBinding() {
    _binding = this;
  }

  static StableSemanticsBinding? _binding;

  /// Initializes this binding once, before runApp or plugin initialization.
  static StableSemanticsBinding ensureInitialized() =>
      _binding ?? StableSemanticsBinding();
}

/// Shared with the widget-test binding so tests exercise the production path.
mixin StableSemanticsUpdates on WidgetsBinding {
  final _stableSemanticsCache = StableSemanticsUpdateCache();

  @protected
  bool get usesStableSemantics =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

  @override
  void initInstances() {
    super.initInstances();
    addSemanticsEnabledListener(() {
      if (!semanticsEnabled) _stableSemanticsCache.clear();
    });
  }

  @override
  ui.SemanticsUpdateBuilder createSemanticsUpdateBuilder() {
    final delegate = super.createSemanticsUpdateBuilder();
    if (!usesStableSemantics) return delegate;
    final views = renderViews.toList(growable: false);
    if (views.length > 1) {
      throw StateError(
        'StableSemanticsBinding supports one Flutter view. '
        'Keep a separate semantics cache per view before adding windows.',
      );
    }
    final owner = views.singleOrNull?.owner?.semanticsOwner;
    return _stableSemanticsCache.wrap(
      delegate,
      isNodeAlive: owner == null
          ? null
          : (id) => owner.getSemanticsNode(id) != null,
      resolveTraversalParent: owner == null
          ? null
          : (id, candidates) {
              final node = owner.getSemanticsNode(id);
              if (node == null) return null;
              final identifier = node
                  .getSemanticsData()
                  .traversalChildIdentifier;
              if (identifier == null) return node.parent?.id;

              // A nested portal can leave its child in both its physical
              // parent's traversal list and its graft parent's list, even in
              // one framework transaction. Match the owner's current portal
              // identifiers, just as SemanticsOwner does before serialization.
              // This also covers an identifier merged from a descendant, for
              // which node.traversalParent can still be the physical parent.
              final matches = candidates.where(
                (candidate) =>
                    owner
                        .getSemanticsNode(candidate)
                        ?.traversalParentIdentifier ==
                    identifier,
              );
              if (matches.length == 1) return matches.single;
              return node.traversalParent?.id;
            },
    );
  }
}

/// Retains framework node data and emits only the complete tree rooted at 0.
///
/// Detached portal nodes are retained while their SemanticsOwner still owns
/// them, so a later attachment does not depend on Flutter resending otherwise
/// unchanged descendants. Disposed nodes are pruned using [isNodeAlive].
class StableSemanticsUpdateCache {
  final Map<int, _CachedNode> _nodes = {};
  final Map<int, Map<Symbol, dynamic>> _actions = {};
  int _revision = 0;

  @visibleForTesting
  Set<int> get cachedNodeIds => Set.unmodifiable(_nodes.keys);

  void clear() {
    _nodes.clear();
    _actions.clear();
    _revision = 0;
  }

  ui.SemanticsUpdateBuilder wrap(
    ui.SemanticsUpdateBuilder delegate, {
    bool Function(int id)? isNodeAlive,
    int? Function(int id, Set<int> candidates)? resolveTraversalParent,
  }) =>
      _StableUpdateBuilder(delegate, this, isNodeAlive, resolveTraversalParent);

  void _emit(
    ui.SemanticsUpdateBuilder delegate,
    Map<int, Map<Symbol, dynamic>> delta,
    Map<int, Map<Symbol, dynamic>> actions,
    bool Function(int id)? isNodeAlive,
    int? Function(int id, Set<int> candidates)? resolveTraversalParent,
  ) {
    final revision = ++_revision;
    for (final entry in delta.entries) {
      _nodes[entry.key] = _CachedNode(entry.value, revision);
    }
    _actions.addAll(actions);
    if (isNodeAlive != null) {
      _nodes.removeWhere((id, _) => !isNodeAlive(id));
    }

    // Do not let the native bridge choose a portal orphan as its first root.
    if (!_nodes.containsKey(0)) return;

    final claims = <int, Set<int>>{};
    for (final entry in _nodes.entries) {
      for (final child in entry.value.children) {
        if (child == 0) {
          throw StateError('The semantics root cannot be a child.');
        }
        claims.putIfAbsent(child, () => <int>{}).add(entry.key);
      }
    }
    final parents = <int, int>{};
    for (final entry in claims.entries) {
      final candidates = entry.value;
      if (candidates.length == 1) {
        parents[entry.key] = candidates.single;
        continue;
      }
      if (resolveTraversalParent != null) {
        final parent = resolveTraversalParent(
          entry.key,
          Set.unmodifiable(candidates),
        );
        if (!candidates.contains(parent)) {
          throw StateError(
            'Semantics node ${entry.key} has parent $parent in its owner, '
            'but its serialized parents are $candidates.',
          );
        }
        parents[entry.key] = parent!;
        continue;
      }

      // Without a live owner, a partial framework reparent can still be
      // resolved if only the new parent's claim is from the latest revision.
      final latest = candidates.reduce(
        (a, b) => _nodes[a]!.revision > _nodes[b]!.revision ? a : b,
      );
      if (candidates.any(
        (id) =>
            id != latest && _nodes[id]!.revision == _nodes[latest]!.revision,
      )) {
        throw StateError(
          'Semantics node ${entry.key} has two parents in one transaction '
          'and no authoritative traversal parent.',
        );
      }
      parents[entry.key] = latest;
    }

    final ordered = <int>[];
    final visiting = <int>{};
    final visited = <int>{};
    void visit(int id) {
      if (visiting.contains(id)) {
        throw StateError('Cycle in semantics tree at node $id.');
      }
      if (!visited.add(id)) return;
      final node = _nodes[id];
      if (node == null) {
        throw StateError('Missing semantics data for attached node $id.');
      }
      visiting.add(id);
      ordered.add(id);
      for (final child in node.children) {
        if (parents[child] == id) visit(child);
      }
      visiting.remove(id);
    }

    visit(0);

    final referencedActions = <int>{};
    for (final id in ordered) {
      final fields = Map<Symbol, dynamic>.of(_nodes[id]!.fields);
      final originalChildren = fields[#childrenInTraversalOrder] as Int32List;
      final traversalChildren = <int>{};
      fields[#childrenInTraversalOrder] = Int32List.fromList([
        for (final child in originalChildren)
          if (parents[child] == id && traversalChildren.add(child)) child,
      ]);
      // Native platforms permit paint/hit-test order to differ after portal
      // grafting. Preserve that order, excluding only truly detached nodes.
      final hitTestChildren = <int>{};
      fields[#childrenInHitTestOrder] = Int32List.fromList([
        for (final child in fields[#childrenInHitTestOrder] as Int32List)
          if (visited.contains(child) && hitTestChildren.add(child)) child,
      ]);
      referencedActions.addAll(fields[#additionalActions] as Int32List);
      Function.apply(delegate.updateNode, const [], fields);
    }
    for (final id in referencedActions) {
      final action = _actions[id];
      if (action != null) {
        Function.apply(delegate.updateCustomAction, const [], action);
      }
    }

    final retainedActions = <int>{};
    for (final node in _nodes.values) {
      retainedActions.addAll(node.fields[#additionalActions] as Int32List);
    }
    _actions.removeWhere((id, _) => !retainedActions.contains(id));
  }
}

class _CachedNode {
  const _CachedNode(this.fields, this.revision);
  final Map<Symbol, dynamic> fields;
  final int revision;
  Int32List get children => fields[#childrenInTraversalOrder] as Int32List;
}

class _StableUpdateBuilder implements ui.SemanticsUpdateBuilder {
  _StableUpdateBuilder(
    this.delegate,
    this.cache,
    this.isNodeAlive,
    this.resolveTraversalParent,
  );

  final ui.SemanticsUpdateBuilder delegate;
  final StableSemanticsUpdateCache cache;
  final bool Function(int id)? isNodeAlive;
  final int? Function(int id, Set<int> candidates)? resolveTraversalParent;
  final Map<int, Map<Symbol, dynamic>> _delta = {};
  final Map<int, Map<Symbol, dynamic>> _actions = {};
  bool _built = false;

  // Forward the complete SDK invocation rather than hand-copying a subset of
  // updateNode's fields. New accessibility fields keep their original values.
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #updateNode) {
      _requireOpen();
      final fields = _copyNodeFields(invocation.namedArguments);
      _delta[fields[#id] as int] = fields;
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
    _requireOpen();
    _actions[id] = {
      #id: id,
      #label: label,
      #hint: hint,
      #overrideId: overrideId,
    };
  }

  @override
  ui.SemanticsUpdate build() {
    _requireOpen();
    _built = true;
    cache._emit(
      delegate,
      _delta,
      _actions,
      isNodeAlive,
      resolveTraversalParent,
    );
    return delegate.build();
  }

  void _requireOpen() {
    if (_built) throw StateError('Semantics update has already been built.');
  }
}

Map<Symbol, dynamic> _copyNodeFields(Map<Symbol, dynamic> original) {
  final copy = Map<Symbol, dynamic>.of(original);
  for (final entry in original.entries) {
    final value = entry.value;
    if (value is Float64List) {
      copy[entry.key] = Float64List.fromList(value);
    } else if (value is Int32List) {
      copy[entry.key] = Int32List.fromList(value);
    } else if (value is List<ui.StringAttribute>) {
      copy[entry.key] = List<ui.StringAttribute>.of(value);
    } else if (value is List<String>) {
      copy[entry.key] = List<String>.of(value);
    }
  }
  return copy;
}
