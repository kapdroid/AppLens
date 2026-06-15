/// The user actions an edge can represent (ARCHITECTURE.md §4). `native` is
/// declared but unimplemented in v1 — permissions are pre-granted, not driven.
enum EdgeAction {
  tap('tap'),
  longPress('long_press'),
  enterText('enter_text'),
  scrollTo('scroll_to'),
  swipe('swipe'),
  back('back'),
  deepLink('deep_link'),
  native('native');

  const EdgeAction(this.yaml);

  /// The YAML spelling of this action (snake_case).
  final String yaml;

  /// Parses [value] into an action, or returns null if unknown.
  static EdgeAction? fromYaml(String value) {
    for (final action in EdgeAction.values) {
      if (action.yaml == value) {
        return action;
      }
    }
    return null;
  }
}

/// The direction a `swipe` edge drags (ARCHITECTURE.md §4). Carried on the edge
/// as `direction:`; the runner translates it into a screen- or widget-centred
/// drag.
enum SwipeDirection {
  up('up'),
  down('down'),
  left('left'),
  right('right');

  const SwipeDirection(this.yaml);

  final String yaml;

  static SwipeDirection? fromYaml(String value) {
    for (final direction in SwipeDirection.values) {
      if (direction.yaml == value) {
        return direction;
      }
    }
    return null;
  }
}
