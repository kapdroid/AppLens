import 'package:applens_core/applens_core.dart';

/// The CI exit code for a run (ARCHITECTURE.md §13): 0 green, 1 red (any
/// soft/hard/blocked outcome), 2 pending-only (team-configurable as pass/fail).
int exitCodeForRun(RunRecord run) {
  var red = false;
  var pending = false;
  for (final visit in run.visits) {
    switch (visit.outcome) {
      case NodeOutcome.failedSoft:
      case NodeOutcome.failedHard:
      case NodeOutcome.blocked:
        red = true;
      case NodeOutcome.pending:
        pending = true;
      case NodeOutcome.passed:
        break;
    }
  }
  if (red) {
    return 1;
  }
  if (pending) {
    return 2;
  }
  return 0;
}
