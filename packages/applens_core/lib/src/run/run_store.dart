import 'run_model.dart';

/// Persists run records (ARCHITECTURE.md §13). The orchestrator records through
/// this seam; the SQLite-file impl and the in-memory impl are interchangeable.
abstract interface class RunStore {
  Future<void> saveRun(RunRecord run);
  Future<RunRecord?> loadRun(String id);
  Future<void> close();
}

/// An in-memory run store — the headless default for tests and the FakeDriver
/// gate, with no native dependency.
class InMemoryRunStore implements RunStore {
  final Map<String, RunRecord> _runs = {};

  @override
  Future<void> saveRun(RunRecord run) async => _runs[run.id] = run;

  @override
  Future<RunRecord?> loadRun(String id) async => _runs[id];

  @override
  Future<void> close() async {}
}
