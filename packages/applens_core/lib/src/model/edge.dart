import '../util/canonical.dart';
import 'edge_action.dart';

/// A directed edge: a user [action] that moves the app from this node to the
/// node identified by [target] (ARCHITECTURE.md §4). Action-specific operands
/// ([key], [text], [uri]) are carried as needed.
class Edge {
  const Edge({
    required this.action,
    required this.target,
    this.key,
    this.text,
    this.uri,
    this.direction,
  });

  final EdgeAction action;

  /// The id of the node this edge leads to.
  final String target;

  /// Widget key the action operates on (tap, long_press, enter_text, scroll_to;
  /// optional for swipe — the widget the drag is centred on).
  final String? key;

  /// Text to enter (enter_text only).
  final String? text;

  /// Deep-link target (deep_link only).
  final String? uri;

  /// Drag direction (swipe only).
  final SwipeDirection? direction;

  /// Returns a copy with [target] replaced (used by the loader to resolve bare
  /// in-module targets to hierarchical ids).
  Edge withTarget(String newTarget) => Edge(
        action: action,
        target: newTarget,
        key: key,
        text: text,
        uri: uri,
        direction: direction,
      );

  Map<String, Object?> toMap() => compactMap({
        'action': action.yaml,
        'target': target,
        'key': key,
        'text': text,
        'uri': uri,
        'direction': direction?.yaml,
      });
}
