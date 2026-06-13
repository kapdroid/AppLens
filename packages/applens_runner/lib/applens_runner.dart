/// AppLens runner: the orchestrator, oracle tiers, and the DriverInterface with
/// its first-party Flutter-SDK action engine. Depends only on applens_core.
library;

export 'src/driver/driver.dart';
export 'src/engine/frame_stabilizer.dart';
export 'src/oracle/oracle.dart';

// Runner loop: orchestrator + fingerprint seam. The pure run model, RunStore
// seam, and SQLite store live in applens_core (shared by the CLI and report).
export 'src/run/fingerprint.dart';
export 'src/run/orchestrator.dart';
export 'src/run/widget_fingerprint_source.dart';
