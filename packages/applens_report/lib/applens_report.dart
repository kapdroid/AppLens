/// AppLens report: static, dependency-free HTML report generation. The
/// generator and the shared graph-render engine land in Session 5; this is the
/// placeholder until then.
library;

/// Schema version of the report data model. Bumped when the report's structure
/// changes in a way older viewers cannot read.
const int reportSchemaVersion = 0;
