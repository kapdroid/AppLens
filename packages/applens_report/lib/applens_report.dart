/// AppLens report: static, dependency-free HTML report generation and the
/// shared graph-render engine (ARCHITECTURE.md §5/§13). Depends only on
/// applens_core.
library;

export 'src/report/flow_analysis.dart';
export 'src/report/graph_view.dart';
export 'src/report/html_report.dart';
export 'src/report/report_status.dart';

/// Schema version of the report data model. Bumped when the report's structure
/// changes in a way older viewers cannot read.
const int reportSchemaVersion = 1;
