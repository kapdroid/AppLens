/// AppLens core: the pure-Dart graph model, schema, validation, path compiler,
/// and the version-control port. Depends on no other AppLens package.
library;

// Graph model.
export 'src/model/assertion.dart';
export 'src/model/edge.dart';
export 'src/model/edge_action.dart';
export 'src/model/flag_constraint.dart';
export 'src/model/graph.dart';
export 'src/model/node.dart';

// YAML parsing and serialization.
export 'src/parse/graph_parser.dart';
export 'src/parse/yaml_writer.dart';

// Path compiler.
export 'src/plan/path_compiler.dart';
export 'src/plan/plan.dart';

// Module-mirrored loading.
export 'src/loader/graph_files.dart';
export 'src/loader/graph_loader.dart';

// Validation.
export 'src/validate/diagnostic.dart';
export 'src/validate/validator.dart';

// Run model + store (pure data; produced by the runner, read by the CLI/report).
export 'src/run/run_model.dart';
export 'src/run/run_store.dart';
export 'src/run/sqlite_run_store.dart';

// Shared.
export 'src/util/source_location.dart';

// Version-control port (Session 0 contract) + the canonical baseline guard.
export 'src/vcs/baseline_guard.dart';
export 'src/vcs/vcs_adapter.dart';
