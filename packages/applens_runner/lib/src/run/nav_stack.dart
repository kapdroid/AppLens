/// The session navigation stack the runner mirrors while walking a path.
///
/// Flutter's `Navigator` is itself a LIFO stack of routes, so `back` is modelled
/// here as a pop: a forward action pushes the node it arrives on, and `back`
/// pops to whatever is beneath. This makes a `back` step *path-relative* — it
/// lands on the screen actually pushed, not a static graph-edge `target` (which
/// is correct only on the canonical path; a long walk can reach a node from a
/// different predecessor). All operations are O(1).
class NavStack {
  NavStack(String entry) : _stack = [entry];

  final List<String> _stack;

  /// The node on top — the screen the walk is currently on.
  String get current => _stack.last;

  /// Where a `back` would land: the node beneath the top, or [current] at the
  /// root (Navigator.maybePop refuses to pop the last route, so back is a no-op
  /// that stays put). Non-mutating, so callers can test the expectation before
  /// committing the pop.
  String get predecessor =>
      _stack.length > 1 ? _stack[_stack.length - 2] : current;

  /// The number of screens on the stack.
  int get depth => _stack.length;

  /// Records a forward navigation that arrived on [node].
  void push(String node) => _stack.add(node);

  /// Pops the current screen (a `back`), returning the new top. A no-op at the
  /// root, mirroring [predecessor].
  String pop() {
    if (_stack.length > 1) _stack.removeLast();
    return _stack.last;
  }

  /// Restarts the stack at [entry] — used when a new path (or a reroute) begins
  /// from an entry node.
  void reset(String entry) => _stack
    ..clear()
    ..add(entry);
}
