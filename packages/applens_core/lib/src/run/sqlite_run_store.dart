import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart';

import 'run_model.dart';
import 'run_store.dart';

/// The run-store v0 backing (ARCHITECTURE.md §13): a SQLite database — one file
/// per run for CI artifact upload, or in-memory for tests. Schema: runs,
/// node_visits, assertion_results, artifacts.
class SqliteRunStore implements RunStore {
  SqliteRunStore(this._db) {
    _migrate();
  }

  /// Opens (or creates) a SQLite database file at [path].
  factory SqliteRunStore.open(String path) =>
      SqliteRunStore(sqlite3.open(path));

  /// An ephemeral in-memory database — used to test the SQLite schema headless.
  factory SqliteRunStore.inMemory() => SqliteRunStore(sqlite3.openInMemory());

  final Database _db;

  void _migrate() {
    _db.execute('''
      CREATE TABLE IF NOT EXISTS runs (
        id TEXT PRIMARY KEY, strategy TEXT, graph_hash TEXT, seed INTEGER);
      CREATE TABLE IF NOT EXISTS node_visits (
        run_id TEXT, step INTEGER, expected_node_id TEXT, matched_node_id TEXT,
        outcome TEXT, unexpected_transition INTEGER);
      CREATE TABLE IF NOT EXISTS assertion_results (
        run_id TEXT, step INTEGER, tier_order INTEGER, type TEXT,
        passed INTEGER, skipped INTEGER, detail TEXT);
      CREATE TABLE IF NOT EXISTS artifacts (
        run_id TEXT, step INTEGER, kind TEXT, description TEXT, bytes BLOB);
    ''');
  }

  @override
  Future<void> saveRun(RunRecord run) async {
    for (final table in const [
      'runs',
      'node_visits',
      'assertion_results',
      'artifacts',
    ]) {
      _db.execute(
        'DELETE FROM $table WHERE ${table == 'runs' ? 'id' : 'run_id'} = ?',
        [run.id],
      );
    }
    _db.execute('INSERT INTO runs VALUES (?, ?, ?, ?)', [
      run.id,
      run.strategy,
      run.graphHash,
      run.seed,
    ]);
    for (final visit in run.visits) {
      _db.execute('INSERT INTO node_visits VALUES (?, ?, ?, ?, ?, ?)', [
        run.id,
        visit.step,
        visit.expectedNodeId,
        visit.matchedNodeId,
        visit.outcome.name,
        visit.isUnexpectedTransition ? 1 : 0,
      ]);
      for (final result in visit.assertions) {
        _db.execute(
            'INSERT INTO assertion_results VALUES (?, ?, ?, ?, ?, ?, ?)', [
          run.id,
          visit.step,
          result.tierOrder,
          result.type,
          result.passed ? 1 : 0,
          result.skipped ? 1 : 0,
          result.detail,
        ]);
      }
      for (final artifact in visit.artifacts) {
        _db.execute('INSERT INTO artifacts VALUES (?, ?, ?, ?, ?)', [
          run.id,
          visit.step,
          artifact.kind,
          artifact.description,
          artifact.bytes, // BLOB — the diff/capture PNG; null when absent
        ]);
      }
    }
  }

  @override
  Future<RunRecord?> loadRun(String id) async {
    final runRows = _db.select('SELECT * FROM runs WHERE id = ?', [id]);
    if (runRows.isEmpty) {
      return null;
    }
    final run = runRows.first;
    final visits = <NodeVisit>[];
    final visitRows = _db.select(
      'SELECT * FROM node_visits WHERE run_id = ? ORDER BY step',
      [id],
    );
    for (final visit in visitRows) {
      final step = visit['step'] as int;
      final assertions = [
        for (final row in _db.select(
          'SELECT * FROM assertion_results WHERE run_id = ? AND step = ?',
          [id, step],
        ))
          AssertionResult(
            tierOrder: row['tier_order'] as int,
            type: row['type'] as String,
            passed: (row['passed'] as int) == 1,
            skipped: (row['skipped'] as int) == 1,
            detail: row['detail'] as String? ?? '',
          ),
      ];
      final artifacts = [
        for (final row in _db.select(
          'SELECT * FROM artifacts WHERE run_id = ? AND step = ?',
          [id, step],
        ))
          Artifact(
            kind: row['kind'] as String,
            description: row['description'] as String? ?? '',
            bytes: row['bytes'] as Uint8List?,
          ),
      ];
      visits.add(
        NodeVisit(
          step: step,
          expectedNodeId: visit['expected_node_id'] as String,
          matchedNodeId: visit['matched_node_id'] as String?,
          outcome: NodeOutcome.values.byName(visit['outcome'] as String),
          assertions: assertions,
          artifacts: artifacts,
        ),
      );
    }
    return RunRecord(
      id: run['id'] as String,
      strategy: run['strategy'] as String,
      graphHash: run['graph_hash'] as String,
      seed: run['seed'] as int,
      visits: visits,
    );
  }

  @override
  Future<void> close() async => _db.dispose();
}
