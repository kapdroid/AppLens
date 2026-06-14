import 'package:applens_runner/applens_runner.dart';

/// What the crawler drives (ARCHITECTURE.md §11). The crawl is breadth-first
/// with restart-and-replay: to reach a frontier state it [reset]s the app to its
/// initial state and replays a path of actions. The production session relaunches
/// the app under `flutter drive` and assembles the route via the same
/// NavigatorObserver the runner uses; tests supply a scripted state machine.
abstract interface class CrawlSession {
  /// Returns the app to its launch state (frontier replay starts from here).
  Future<void> reset();

  AppLensDriver get driver;

  /// The route probe used — with the widget tree — to cluster states (§11).
  FingerprintSource get fingerprint;
}

/// Bounds the crawl (ARCHITECTURE.md §11): a prospective user gives the tool
/// minutes, not a full traversal. [maxStates] caps distinct states discovered;
/// [maxDepth] caps how deep a replay path goes.
class CrawlBudget {
  const CrawlBudget({this.maxStates = 40, this.maxDepth = 8});

  final int maxStates;
  final int maxDepth;
}

/// Widget-key substrings that mark an action as destructive (delete/submit/pay).
/// The crawler skips these unless explicitly allowed, so a crawl never places an
/// order or wipes data (ARCHITECTURE.md §11).
/// Matched against a widget key's *tokens* (split on separators and camelCase),
/// not as raw substrings — so `btn_reorder` / `border` / `buyer` are not
/// mistaken for destructive, while `transfer` / `wipe` are caught.
const Set<String> defaultDestructiveKeywords = {
  'delete',
  'remove',
  'submit',
  'pay',
  'buy',
  'checkout',
  'confirm',
  'purchase',
  'order',
  'send',
  'logout',
  'signout',
  'transfer',
  'withdraw',
  'wipe',
  'erase',
  'cancel',
  'destroy',
  'discard',
};
