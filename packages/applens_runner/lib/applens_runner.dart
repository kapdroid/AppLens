/// AppLens runner: the orchestrator, oracle tiers, and the DriverInterface with
/// its first-party Flutter-SDK action engine. Depends on applens_core and, for
/// the tier-3 pixel comparison, the standalone applens_compare (no fork — §14).
library;

export 'src/driver/driver.dart';
export 'src/engine/frame_stabilizer.dart';
export 'src/oracle/oracle.dart';
export 'src/visual/baseline_source.dart';

// Runner loop: orchestrator + fingerprint seam. The pure run model, RunStore
// seam, and SQLite store live in applens_core (shared by the CLI and report).
export 'src/run/fingerprint.dart';
export 'src/run/orchestrator.dart';
export 'src/run/widget_fingerprint_source.dart';
