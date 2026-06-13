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
