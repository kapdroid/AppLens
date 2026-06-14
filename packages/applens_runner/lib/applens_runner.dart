/// AppLens runner: the orchestrator, oracle tiers, and the DriverInterface with
/// its first-party Flutter-SDK action engine. Depends on applens_core and, for
/// the tier-3 pixel comparison, the standalone applens_compare (no fork — §14).
library;

export 'src/driver/driver.dart';
export 'src/engine/frame_stabilizer.dart';
export 'src/oracle/oracle.dart';
export 'src/visual/baseline_recorder.dart';
export 'src/visual/baseline_source.dart';
export 'src/visual/proposal_source.dart';

// Runner loop: orchestrator + fingerprint seam. The pure run model, RunStore
// seam, and SQLite store live in applens_core (shared by the CLI and report).
export 'src/run/fingerprint.dart';
export 'src/run/orchestrator.dart';
export 'src/run/widget_fingerprint_source.dart';

// Tree-shape hash (tier-2): shared with the crawler's state clustering (§11),
// so "tree shape" has one definition, not a fork.
export 'src/run/tier2.dart' show layoutHash;
