import 'dart:convert';
import 'dart:io';

import 'package:applens_core/applens_core.dart';
import 'package:applens_llm/applens_llm.dart';
import 'package:applens_report/applens_report.dart';
import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:yaml/yaml.dart';

import 'git_commits.dart';
import 'shell.dart';
import 'templates.dart';
import 'term.dart';

/// The AppLens command-line entrypoint. Output is injected so commands are
/// testable headless; each command returns a process exit code. [triageProvider]
/// and [triageCommits] are seams for testing `triage` without a live key or a
/// git checkout — production builds them from flags and the environment.
class AppLensCli {
  AppLensCli({
    StringSink? out,
    LlmProvider? triageProvider,
    CommitSource? triageCommits,
    LlmProvider? authorProvider,
  })  : _out = out ?? stdout,
        _triageProvider = triageProvider,
        _triageCommits = triageCommits,
        _authorProvider = authorProvider;

  final StringSink _out;
  final LlmProvider? _triageProvider;
  final CommitSource? _triageCommits;
  final LlmProvider? _authorProvider;

  Future<int> run(List<String> args) async {
    // No subcommand (or `start`) → the interactive shell (the claude-style
    // session); an explicit command keeps the one-shot path for CI, scripts,
    // and `--help`.
    if (args.isEmpty || (args.length == 1 && args.first == 'start')) {
      return _runInteractive();
    }
    return _runOnce(args);
  }

  Future<int> _runOnce(List<String> args) async {
    final runner = CommandRunner<int>(
      'applens',
      'Graph-based autonomous QA for Flutter.',
    )
      ..argParser.addFlag('no-color',
          negatable: false, help: 'Disable colored output.')
      ..addCommand(_ValidateCommand(_out))
      ..addCommand(_PlanCommand(_out))
      ..addCommand(_GraphCommand(_out))
      ..addCommand(_ReportCommand(_out))
      ..addCommand(_InitCommand(_out))
      ..addCommand(_RunCommand(_out))
      ..addCommand(_AllCommand(_out))
      ..addCommand(_ApproveCommand(_out))
      ..addCommand(_TriageCommand(_out,
          provider: _triageProvider, commits: _triageCommits))
      ..addCommand(_AuthorCommand(_out, provider: _authorProvider))
      ..addCommand(_CrawlCommand(_out));
    try {
      return await runner.run(args) ?? 0;
    } on UsageException catch (error) {
      _out.writeln(error.message);
      return 64;
    }
  }

  Future<int> _runInteractive() {
    final shell = Shell(
      out: _out,
      style: Style.forSink(_out),
      dispatch: _runOnce,
    );
    return shell.repl();
  }
}

Graph? _load(String dir, StringSink out) {
  try {
    return loadGraph(dir);
  } on GraphParseException catch (error) {
    out.writeln('parse error: $error');
    return null;
  }
}

/// Reads a run record from a `run.json`, returning null with a clear message on
/// a missing/malformed file instead of letting an exception reach the user as a
/// stack trace (a truncated `run.json` is a real CI scenario).
RunRecord? _loadRunJson(String path, StringSink out) {
  final file = File(path);
  if (!file.existsSync()) {
    out.writeln('no run file: $path');
    return null;
  }
  try {
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! Map) {
      out.writeln('run file $path is not a JSON object');
      return null;
    }
    return RunRecord.fromMap(decoded.cast<String, Object?>());
  } on FormatException catch (error) {
    out.writeln('run file $path is not valid JSON: ${error.message}');
    return null;
  } on TypeError {
    out.writeln('run file $path is missing required run fields');
    return null;
  } on ArgumentError {
    out.writeln('run file $path has an invalid value (e.g. unknown outcome)');
    return null;
  }
}

/// Loads a run from a SQLite `.db` store, returning null with a clear message on
/// a missing/corrupt file instead of a stack trace — same graceful-load contract
/// as [_loadRunJson] (a corrupt `.db` download is a real CI scenario). Catches
/// `Exception` (the SqliteException from a non-database file is one); programming
/// `Error`s still surface.
Future<RunRecord?> _loadRunDb(String path, String runId, StringSink out) async {
  if (!File(path).existsSync()) {
    out.writeln('no run file: $path');
    return null;
  }
  SqliteRunStore? store;
  try {
    store = SqliteRunStore.open(path);
    final record = await store.loadRun(runId);
    if (record == null) {
      out.writeln('no run "$runId" in $path');
    }
    return record;
  } on Exception {
    out.writeln('run store $path is not a valid AppLens run database');
    return null;
  } finally {
    await store?.close();
  }
}

/// Builds the configured LLM provider from `--provider/--model/--api-key-env`
/// (BYO-key — the key is read from the environment, never a flag). Returns null
/// with a message when the provider is unknown or the key is unset. Shared by
/// the sidecar commands (triage, author).
LlmProvider? _buildLlmProvider(
    ArgResults args, StringSink out, String purpose) {
  final kind = args.option('provider');
  if (kind != 'claude') {
    out.writeln('unknown provider "$kind" (supported: claude)');
    return null;
  }
  final envVar = args.option('api-key-env')!;
  final key = Platform.environment[envVar];
  if (key == null || key.isEmpty) {
    out.writeln('no API key in \$$envVar — set it (BYO-key) to run $purpose');
    return null;
  }
  return ClaudeProvider(apiKey: key, model: args.option('model')!);
}

/// The `flutter drive` args that run the on-device entrypoint; the entrypoint
/// reads the dart-defines to compile the plan, so one host runs any strategy.
List<String> _flutterDriveArgs({
  required String entrypoint,
  required String strategy,
  required String seed,
  required String soakSteps,
  String? device,
}) =>
    [
      'drive',
      '--driver=test_driver/integration_test.dart',
      '--target=$entrypoint',
      '--dart-define=APPLENS_STRATEGY=$strategy',
      '--dart-define=APPLENS_SEED=$seed',
      '--dart-define=APPLENS_SOAK_STEPS=$soakSteps',
      if (device != null) ...['-d', device],
    ];

/// The adb permission grants from applens.yaml, pre-granted so native dialogs
/// never appear mid-walk (ARCHITECTURE.md §7/§10).
List<List<String>> _permissionGrants(_RunConfig config) => [
      for (final permission in config.permissions)
        ['shell', 'pm', 'grant', config.appId, permission],
    ];

/// Reads app id + permissions from applens.yaml (defaults when absent).
_RunConfig _readRunConfig(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    return const _RunConfig('<applicationId>', []);
  }
  final doc = loadYaml(file.readAsStringSync());
  if (doc is! YamlMap) {
    return const _RunConfig('<applicationId>', []);
  }
  final permissions = doc['permissions'];
  return _RunConfig(
    doc['app_id']?.toString() ?? '<applicationId>',
    permissions is YamlList
        ? [for (final item in permissions) item.toString()]
        : const [],
  );
}

/// Pre-grants permissions, then walks the plan on the device via `flutter
/// drive`, forwarding its output live (Process.start, not the buffered
/// Process.run) so the terminal shows progress. Returns the flutter exit code.
Future<int> _driveDevice({
  required StringSink out,
  required Style style,
  required List<List<String>> grants,
  required List<String> flutterArgs,
  required String device,
}) async {
  for (final grant in grants) {
    await Process.run('adb', ['-s', device, ...grant]);
  }
  final proc = await Process.start('flutter', flutterArgs,
      runInShell: Platform.isWindows);
  final outDone = proc.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .forEach((line) => out.writeln(style.dim(line)));
  final errDone = proc.stderr
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .forEach((line) => out.writeln(style.warn(line)));
  final code = await proc.exitCode;
  await outDone;
  await errDone;
  return code;
}

/// Renders [record] to [outPath] and returns the verdict exit code (0 green /
/// 1 red / 2 pending). Shared by `report` and `all`.
int _writeReport({
  required StringSink out,
  required Style style,
  required RunRecord record,
  required Graph graph,
  required String outPath,
  TriageReport? triage,
}) {
  File(outPath)
      .writeAsStringSync(renderRunReport(record, graph, triage: triage));
  out.writeln(style.ok('✓ wrote $outPath'));
  // Triage is advisory (ARCHITECTURE.md §9): the exit code reflects the run.
  return exitCodeForRun(record);
}

/// Loads an optional triage.json. Returns `(true, null)` when [path] is null,
/// `(false, null)` on a missing/malformed file (after explaining why), and
/// `(true, report)` on success — the graceful-load contract of [_loadRunJson].
(bool, TriageReport?) _loadTriage(String? path, StringSink out) {
  if (path == null) {
    return (true, null);
  }
  if (!File(path).existsSync()) {
    out.writeln('no triage file: $path');
    return (false, null);
  }
  try {
    final decoded = jsonDecode(File(path).readAsStringSync());
    if (decoded is! Map) {
      out.writeln('triage file $path is not a JSON object');
      return (false, null);
    }
    return (true, TriageReport.fromMap(decoded.cast<String, Object?>()));
  } on FormatException catch (error) {
    out.writeln('triage file $path is not valid JSON: ${error.message}');
    return (false, null);
  } on TypeError {
    out.writeln('triage file $path is missing required triage fields');
    return (false, null);
  } on ArgumentError {
    out.writeln('triage file $path has an invalid value');
    return (false, null);
  }
}

abstract class _Base extends Command<int> {
  _Base(this.out);
  final StringSink out;

  /// Colored-output styler — on only for a real terminal (off when piped/CI/
  /// `NO_COLOR`/`--no-color`, and whenever `out` isn't `stdout`, e.g. tests).
  Style get style =>
      Style.forSink(out, noColorFlag: globalResults?.flag('no-color') ?? false);

  String? requirePositional(String usage) {
    final rest = argResults!.rest;
    if (rest.isEmpty) {
      out.writeln('usage: applens $usage');
      return null;
    }
    return rest.first;
  }
}

class _ValidateCommand extends _Base {
  _ValidateCommand(super.out);
  @override
  String get name => 'validate';
  @override
  String get description => 'Validate a qa_graph directory.';

  @override
  Future<int> run() async {
    final dir = requirePositional('validate <qa_graph>');
    if (dir == null) {
      return 64;
    }
    final graph = _load(dir, out);
    if (graph == null) {
      return 1;
    }
    final diagnostics = validateGraph(graph);
    for (final diagnostic in diagnostics) {
      out.writeln(diagnostic.toString());
    }
    final errors = diagnostics.where((d) => d.isError).length;
    out.writeln(
      errors == 0
          ? style.ok('✓ valid (${graph.nodes.length} nodes)')
          : style.fail('✗ $errors error(s)'),
    );
    return errors == 0 ? 0 : 1;
  }
}

class _PlanCommand extends _Base {
  _PlanCommand(super.out) {
    argParser
      ..addOption('strategy',
          defaultsTo: 'smoke', help: 'smoke | regression | impact')
      ..addMultiOption('changed-module',
          help: 'impact: a module a PR touched; its nodes become the targets.')
      ..addMultiOption('changed-node',
          help: 'impact: an exact node id a PR touched.')
      ..addOption('out', help: 'Write the plan YAML to this file.');
  }
  @override
  String get name => 'plan';
  @override
  String get description => 'Compile a test plan from a qa_graph directory.';

  @override
  Future<int> run() async {
    final dir = requirePositional(
        'plan <qa_graph> [--strategy] [--changed-module] [--changed-node] [--out]');
    if (dir == null) {
      return 64;
    }
    final graph = _load(dir, out);
    if (graph == null) {
      return 1;
    }
    if (validateGraph(graph).any((d) => d.isError)) {
      out.writeln(
          style.fail('✗ graph does not validate; fix it before planning'));
      return 1;
    }
    final strategy = PlanStrategy.fromYaml(argResults!.option('strategy')!);
    if (strategy == null) {
      out.writeln('unknown strategy "${argResults!.option('strategy')}"');
      return 64;
    }
    final changedNodeIds = <String>{
      ...argResults!.multiOption('changed-node'),
      ...nodeIdsInModules(
          graph, argResults!.multiOption('changed-module').toSet()),
    };
    final plan =
        compilePlan(graph, strategy: strategy, changedNodeIds: changedNodeIds);
    final yaml = writeYaml(plan.toMap());
    final outPath = argResults!.option('out');
    if (outPath == null) {
      out.write(yaml);
    } else {
      File(outPath).writeAsStringSync(yaml);
      out.writeln(style.ok('✓ wrote $outPath'));
    }
    return 0;
  }
}

class _ReportCommand extends _Base {
  _ReportCommand(super.out) {
    argParser
      ..addOption('run-id', defaultsTo: 'run')
      ..addOption('triage',
          help:
              'A triage.json (from `applens triage`) to fold into the report.')
      ..addOption('out', defaultsTo: 'applens_report.html');
  }
  @override
  String get name => 'report';
  @override
  String get description =>
      'Render an HTML report from a run store — .db (SQLite) or .json (exit 0/1/2).';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.length < 2) {
      out.writeln(
          'usage: applens report <qa_graph> <run.db|run.json> [--run-id] [--out]');
      return 64;
    }
    final graph = _load(rest[0], out);
    if (graph == null) {
      return 1;
    }
    final RunRecord? record;
    if (rest[1].endsWith('.json')) {
      // The on-device path: a run serialized off the device via flutter drive.
      record = _loadRunJson(rest[1], out);
      if (record == null) {
        return 1; // _loadRunJson already explained why
      }
    } else {
      record = await _loadRunDb(rest[1], argResults!.option('run-id')!, out);
      if (record == null) {
        return 1; // _loadRunDb already explained why
      }
    }
    final (triageOk, triage) = _loadTriage(argResults!.option('triage'), out);
    if (!triageOk) {
      return 1;
    }
    final outPath = argResults!.option('out')!;
    return _writeReport(
      out: out,
      style: style,
      record: record,
      graph: graph,
      outPath: outPath,
      triage: triage,
    );
  }
}

/// Promotes a drifted capture/snapshot from a run into the node's approved
/// baseline on disk — the local, no-GitHub equivalent of approving a baseline
/// proposal. It writes the new golden/snapshot and swaps the hash in the node's
/// YAML, then leaves the change for the human to review (`git diff`) and commit:
/// this *is* the human-approval step of the proposal mechanism (CLAUDE.md), not
/// a run silently rewriting the graph.
class _ApproveCommand extends _Base {
  _ApproveCommand(super.out) {
    argParser.addOption('node',
        help: 'The node id whose drift to approve.', mandatory: true);
  }
  @override
  String get name => 'approve';
  @override
  String get description =>
      'Promote a run\'s drifted capture/snapshot into the node\'s approved '
      'baseline on disk (local approve — review the diff, then commit).';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.length < 2) {
      out.writeln('usage: applens approve <qa_graph> <run.json> --node <id>');
      return 64;
    }
    final dir = rest[0];
    final graph = _load(dir, out);
    if (graph == null) {
      return 1;
    }
    final record = _loadRunJson(rest[1], out);
    if (record == null) {
      return 1;
    }
    final nodeId = argResults!.option('node')!;
    final node = graph.byId[nodeId];
    if (node == null || node.source == null) {
      out.writeln('no node "$nodeId" with a source file in the graph');
      return 1;
    }
    // The node's drift evidence — at most one tier-3 'capture' (new golden) and
    // one tier-2.5 'structural' (new snapshot). First-reach only is enforced by
    // the orchestrator, but a node reached as the target of two paths can record
    // two; take the first of each kind so we never write an orphaned golden.
    Artifact? firstOfKind(String kind) {
      for (final visit in record.visits) {
        if (visit.expectedNodeId != nodeId) continue;
        for (final a in visit.artifacts) {
          if (a.kind == kind && a.bytes != null) return a;
        }
      }
      return null;
    }

    final capture = firstOfKind('capture');
    final structural = firstOfKind('structural');
    if (capture == null && structural == null) {
      out.writeln('no drift to approve for "$nodeId" in ${rest[1]}');
      return 1;
    }

    // node.source.source is the path loadGraph read the node from.
    final file = File(node.source!.source);
    var yaml = file.readAsStringSync();
    final changes = <String>[];

    String? hexOf(Artifact a) {
      // Trust the description only when it is the content-address form; a
      // malformed run.json must fail cleanly, not crash on substring.
      if (!a.description.startsWith('sha256:')) {
        out.writeln('artifact for "$nodeId" has no sha256 reference '
            '("${a.description}") — not a valid AppLens run');
        return null;
      }
      return a.description.substring('sha256:'.length);
    }

    if (capture != null) {
      final old = _approvedImage(node);
      final hex = hexOf(capture);
      if (old == null) {
        out.writeln('"$nodeId" has no approved visual baseline to update');
        return 1;
      }
      if (hex == null) return 1;
      File('$dir/goldens/$hex.png')
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync(capture.bytes!);
      // replaceFirst (not All): swap only this baseline's ref, never a shared
      // sibling context or a `replaced:` audit field that holds the same hash.
      yaml = yaml.replaceFirst(old, capture.description);
      changes.add('golden $old → ${capture.description}');
    }
    if (structural != null) {
      final old = _approvedSnapshot(node);
      final hex = hexOf(structural);
      if (old == null) {
        out.writeln('"$nodeId" has no approved structural baseline to update');
        return 1;
      }
      if (hex == null) return 1;
      File('$dir/structural/$hex.json')
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync(structural.bytes!);
      yaml = yaml.replaceFirst(old, structural.description);
      changes.add('snapshot $old → ${structural.description}');
    }
    file.writeAsStringSync(yaml);
    out
      ..writeln(style.ok('✓ approved "$nodeId" in ${node.source!.source}:'))
      ..writeln('  ${changes.join('\n  ')}')
      ..writeln('review with `git diff` and commit to record the baseline.');
    return 0;
  }

  String? _approvedImage(Node node) {
    for (final b in node.payload.visualBaselines) {
      if (b.state == BaselineState.approved) return b.image;
    }
    return null;
  }

  String? _approvedSnapshot(Node node) {
    for (final b in node.payload.structuralBaselines) {
      if (b.state == BaselineState.approved) return b.snapshot;
    }
    return null;
  }
}

class _TriageCommand extends _Base {
  _TriageCommand(super.out, {LlmProvider? provider, CommitSource? commits})
      : _provider = provider,
        _commits = commits {
    argParser
      ..addOption('provider',
          defaultsTo: 'claude', help: 'LLM provider: claude.')
      ..addOption('model', defaultsTo: 'claude-opus-4-8')
      ..addOption('api-key-env',
          defaultsTo: 'ANTHROPIC_API_KEY',
          help: 'Env var holding the provider API key (BYO-key).')
      ..addOption('since',
          help:
              'Git ref of the last green run; commits since it are correlated.')
      ..addOption('out', defaultsTo: 'triage.json');
  }

  final LlmProvider? _provider;
  final CommitSource? _commits;

  @override
  String get name => 'triage';
  @override
  String get description =>
      'Triage a run\'s failures with an LLM provider (advisory — writes '
      'verdicts + baseline proposals to triage.json; never gates the run).';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.length < 2) {
      out.writeln('usage: applens triage <qa_graph> <run.json> '
          '[--provider] [--since] [--out]');
      return 64;
    }
    final graph = _load(rest[0], out);
    if (graph == null) return 1;
    final record = _loadRunJson(rest[1], out);
    if (record == null) return 1;

    final provider = _provider ?? _buildProvider();
    if (provider == null) return 64;
    final commits = _commits ??
        GitCommitSource(
          sinceRef: argResults!.option('since'),
          modulePaths: _modulePaths(rest[0]),
        );

    final report = await triageRun(
      record,
      graph,
      commits,
      provider,
      providerName: argResults!.option('provider'),
    );

    final outPath = argResults!.option('out')!;
    File(outPath).writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(report.toMap()));
    out.writeln(style.ok('✓ triaged ${report.verdicts.length} failure(s), '
        '${report.proposals.length} proposal(s) → $outPath'));
    // Advisory (ARCHITECTURE.md §9): triage never changes the run verdict.
    // `applens report` still owns the pass/fail exit code.
    return 0;
  }

  LlmProvider? _buildProvider() =>
      _buildLlmProvider(argResults!, out, 'triage');

  /// Reads an optional `module_paths: {module: [glob, ...]}` map from the
  /// graph's applens.yaml, used to scope `git log` per module.
  Map<String, List<String>> _modulePaths(String qaGraphDir) {
    final file = File('$qaGraphDir/applens.yaml');
    if (!file.existsSync()) return const {};
    final yaml = loadYaml(file.readAsStringSync());
    final map = yaml is YamlMap ? yaml['module_paths'] : null;
    if (map is! YamlMap) return const {};
    return {
      for (final entry in map.entries)
        '${entry.key}': [
          if (entry.value is YamlList)
            for (final p in entry.value as YamlList) '$p',
        ],
    };
  }
}

class _InitCommand extends _Base {
  _InitCommand(super.out);
  @override
  String get name => 'init';
  @override
  String get description =>
      'Scaffold qa_graph/, applens.yaml, and the runner entrypoint.';

  @override
  Future<int> run() async {
    final root = argResults!.rest.isEmpty ? '.' : argResults!.rest.first;
    final files = <String, String>{
      '$root/qa_graph/applens.yaml': applensYamlTemplate,
      '$root/qa_graph/modules/app/app.module.yaml': starterModuleManifest,
      '$root/qa_graph/modules/app/nodes/home.yaml': starterNode,
      '$root/integration_test/applens_entry.dart': entrypointTemplate,
    };
    for (final entry in files.entries) {
      final file = File(entry.key);
      if (file.existsSync()) {
        out.writeln('skip (exists): ${entry.key}');
        continue;
      }
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(entry.value);
      out.writeln('created: ${entry.key}');
    }
    out.writeln(style.ok(
        '✓ initialized — edit the entrypoint import, then `applens run qa_graph`'));
    return 0;
  }
}

class _RunCommand extends _Base {
  _RunCommand(super.out) {
    argParser
      ..addOption('strategy', defaultsTo: 'smoke')
      ..addOption('seed', defaultsTo: '0', help: 'Seed for the soak walk.')
      ..addOption('soak-steps',
          defaultsTo: '40', help: 'Step budget for the soak walk.')
      ..addOption('entrypoint',
          defaultsTo: 'integration_test/applens_entry.dart')
      ..addOption('device',
          help: 'Target device id (`flutter -d` / adb -s). Required on-device.')
      ..addFlag('dry-run',
          help: 'Print the device commands without executing.');
  }
  @override
  String get name => 'run';
  @override
  String get description =>
      'Pre-grant permissions and execute the plan on a device (needs an emulator).';

  @override
  Future<int> run() async {
    final dir =
        requirePositional('run <qa_graph> [--strategy] [--device] [--dry-run]');
    if (dir == null) {
      return 64;
    }
    final graph = _load(dir, out);
    if (graph == null) {
      return 1;
    }
    if (validateGraph(graph).any((d) => d.isError)) {
      out.writeln('✗ graph does not validate');
      return 1;
    }
    final config = _readRunConfig('$dir/applens.yaml');
    final device = argResults!.option('device');
    final grants = _permissionGrants(config);
    // `flutter drive` runs the entrypoint ON the device and returns the run
    // record to the host (build/applens/run.json) via the integration_test
    // driver's responseData — no adb pull, no on-device SQLite needed.
    final flutterArgs = _flutterDriveArgs(
      entrypoint: argResults!.option('entrypoint')!,
      strategy: argResults!.option('strategy')!,
      seed: argResults!.option('seed')!,
      soakSteps: argResults!.option('soak-steps')!,
      device: device,
    );
    for (final grant in grants) {
      out.writeln(style.dim('adb ${grant.join(' ')}'));
    }
    out.writeln(style.dim('flutter ${flutterArgs.join(' ')}'));

    if (argResults!.flag('dry-run')) {
      return 0;
    }
    if (device == null) {
      out.writeln(
          style.fail('✗ --device is required to run on an emulator/device'));
      return 64;
    }
    final code = await _driveDevice(
      out: out,
      style: style,
      grants: grants,
      flutterArgs: flutterArgs,
      device: device,
    );
    return code == 0 ? 0 : 1;
  }
}

class _RunConfig {
  const _RunConfig(this.appId, this.permissions);
  final String appId;
  final List<String> permissions;
}

/// The one-command pipeline: validate → device walk (the four-tier oracle, so
/// both the semantic and visual screen comparisons run) → render the report →
/// open it → exit with the report's verdict (0 green / 1 red / 2 pending).
/// Defaults to regression. `--no-walk` re-renders the last run without walking.
class _AllCommand extends _Base {
  _AllCommand(super.out) {
    argParser
      ..addOption('strategy', defaultsTo: 'regression')
      ..addOption('seed', defaultsTo: '0')
      ..addOption('soak-steps', defaultsTo: '40')
      ..addOption('entrypoint',
          defaultsTo: 'integration_test/applens_entry.dart')
      ..addOption('device',
          help: 'Target device id (`flutter -d`). Required for the walk.')
      ..addOption('out', defaultsTo: 'build/applens/report.html')
      ..addOption('run-json', defaultsTo: 'build/applens/run.json')
      ..addOption('triage',
          help:
              'A triage.json (from `applens triage`) to fold into the report.')
      ..addFlag('no-open',
          negatable: false, help: 'Do not open the report when done.')
      ..addFlag('no-walk',
          negatable: false,
          help: 'Skip the device walk; render the existing run.json.')
      ..addFlag('dry-run',
          help: 'Print the pipeline without touching a device.');
  }
  @override
  String get name => 'all';
  @override
  String get description =>
      'Validate → walk on a device → report → open, exiting with the verdict.';

  @override
  Future<int> run() async {
    final dir = requirePositional(
        'all <qa_graph> --device <id> [--strategy] [--no-open] [--no-walk]');
    if (dir == null) {
      return 64;
    }
    final s = style;
    final outPath = argResults!.option('out')!;
    final runJson = argResults!.option('run-json')!;
    final graph = _load(dir, out);
    if (graph == null) {
      return 1;
    }

    if (!argResults!.flag('no-walk')) {
      out.writeln(s.step('▸ [1/5] validate'));
      if (validateGraph(graph).any((d) => d.isError)) {
        out.writeln(s.fail('✗ graph does not validate; fix it before running'));
        return 1;
      }
      out.writeln(s.ok('✓ valid (${graph.nodes.length} nodes)'));

      final strategy = argResults!.option('strategy')!;
      out.writeln(s.step('▸ [2/5] plan ($strategy)'));

      out.writeln(s.step('▸ [3/5] device walk'));
      final device = argResults!.option('device');
      final grants = _permissionGrants(_readRunConfig('$dir/applens.yaml'));
      final flutterArgs = _flutterDriveArgs(
        entrypoint: argResults!.option('entrypoint')!,
        strategy: strategy,
        seed: argResults!.option('seed')!,
        soakSteps: argResults!.option('soak-steps')!,
        device: device,
      );
      for (final grant in grants) {
        out.writeln(s.dim('adb ${grant.join(' ')}'));
      }
      out.writeln(s.dim('flutter ${flutterArgs.join(' ')}'));
      if (argResults!.flag('dry-run')) {
        return 0;
      }
      if (device == null) {
        out.writeln(
            s.fail('✗ --device is required to run on an emulator/device'));
        return 64;
      }
      final code = await _driveDevice(
        out: out,
        style: s,
        grants: grants,
        flutterArgs: flutterArgs,
        device: device,
      );
      if (code != 0 && !File(runJson).existsSync()) {
        out.writeln(s.fail('✗ device walk failed (flutter exit $code); '
            'no $runJson — not rendering a report'));
        return 1;
      }
    }

    out.writeln(s.step('▸ [4/5] report'));
    if (!File(runJson).existsSync()) {
      out.writeln(s.fail('✗ no run record at $runJson — cannot render'));
      return 1;
    }
    final (triageOk, triage) = _loadTriage(argResults!.option('triage'), out);
    if (!triageOk) {
      return 1;
    }
    final record = _loadRunJson(runJson, out);
    if (record == null) {
      return 1;
    }
    final verdict = _writeReport(
      out: out,
      style: s,
      record: record,
      graph: graph,
      outPath: outPath,
      triage: triage,
    );

    out.writeln(s.step('▸ [5/5] open'));
    if (!argResults!.flag('no-open') && stdout.hasTerminal) {
      await openInBrowser(outPath, out, s);
    } else {
      out.writeln(s.dim('(skipped — '
          '${argResults!.flag('no-open') ? '--no-open' : 'not a terminal'})'));
    }

    switch (verdict) {
      case 0:
        out.writeln(s.ok('✓ GREEN — all assertions passed'));
      case 2:
        out.writeln(
            s.warn('⚠ PENDING — baselines awaiting approval; see $outPath'));
      default:
        out.writeln(s.fail('✗ RED — see $outPath'));
    }
    return verdict;
  }
}

class _AuthorCommand extends _Base {
  _AuthorCommand(super.out, {LlmProvider? provider}) : _provider = provider {
    argParser
      ..addOption('module',
          defaultsTo: 'app', help: 'Module the draft nodes belong to.')
      ..addOption('provider',
          defaultsTo: 'claude', help: 'LLM provider: claude.')
      ..addOption('model', defaultsTo: 'claude-opus-4-8')
      ..addOption('api-key-env',
          defaultsTo: 'ANTHROPIC_API_KEY',
          help: 'Env var holding the provider API key (BYO-key).')
      ..addOption('out', defaultsTo: 'draft_graph.yaml');
  }

  final LlmProvider? _provider;

  @override
  String get name => 'author';
  @override
  String get description =>
      'Draft qa_graph nodes from a prose test case via an LLM provider '
      '(BYO-key; advisory — writes a draft graph for review, never gates).';

  @override
  Future<int> run() async {
    final testFile =
        requirePositional('author <test-file> [--module] [--out] [--provider]');
    if (testFile == null) return 64;
    if (!File(testFile).existsSync()) {
      out.writeln('no test file: $testFile');
      return 1;
    }
    final provider = _provider ?? _buildLlmProvider(argResults!, out, 'author');
    if (provider == null) return 64;

    final Graph graph;
    try {
      graph = await author(
        File(testFile).readAsStringSync(),
        provider,
        module: argResults!.option('module')!,
      );
    } on LlmException catch (error) {
      out.writeln('author failed: ${error.message}');
      return 1;
    }
    final outPath = argResults!.option('out')!;
    File(outPath).writeAsStringSync(writeYaml(graph.toMap()));
    out.writeln(style.ok('✓ drafted ${graph.nodes.length} node(s) → $outPath '
        '(review, refine, and open a PR)'));
    return 0;
  }
}

class _CrawlCommand extends _Base {
  _CrawlCommand(super.out) {
    argParser
      ..addOption('device',
          help: 'Target device id (`flutter -d`). Required on-device.')
      ..addOption('entrypoint',
          defaultsTo: 'integration_test/applens_crawl_entry.dart')
      ..addOption('module', defaultsTo: 'app')
      ..addOption('budget', defaultsTo: '40', help: 'Max states to discover.')
      ..addOption('depth', defaultsTo: '8', help: 'Max replay depth.')
      ..addOption('out', defaultsTo: 'build/applens/draft_graph.yaml')
      ..addFlag('allow-destructive',
          help: 'Permit delete/submit/pay actions during the crawl.')
      ..addFlag('dry-run', help: 'Print the device command without executing.');
  }

  @override
  String get name => 'crawl';
  @override
  String get description =>
      'Explore the app on a device and propose a draft graph (needs an '
      'emulator; the draft is a PR, never auto-merged).';

  @override
  Future<int> run() async {
    final device = argResults!.option('device');
    final entrypoint = argResults!.option('entrypoint')!;
    // Crawl parameters reach the on-device entrypoint as dart-defines.
    final flutterArgs = [
      'drive',
      '--driver=test_driver/integration_test.dart',
      '--target=$entrypoint',
      '--dart-define=APPLENS_CRAWL_MODULE=${argResults!.option('module')}',
      '--dart-define=APPLENS_CRAWL_BUDGET=${argResults!.option('budget')}',
      '--dart-define=APPLENS_CRAWL_DEPTH=${argResults!.option('depth')}',
      '--dart-define=APPLENS_CRAWL_ALLOW_DESTRUCTIVE='
          '${argResults!.flag('allow-destructive')}',
      if (device != null) ...['-d', device],
    ];
    out.writeln('flutter ${flutterArgs.join(' ')}');

    if (argResults!.flag('dry-run')) {
      return 0;
    }
    if (device == null) {
      out.writeln(
          style.fail('✗ --device is required to crawl on an emulator/device'));
      return 64;
    }
    final result = await Process.run('flutter', flutterArgs);
    out
      ..writeln(result.stdout)
      ..writeln(result.stderr);
    return result.exitCode == 0 ? 0 : 1;
  }
}

class _GraphCommand extends Command<int> {
  _GraphCommand(StringSink out) {
    addSubcommand(_GraphStatsCommand(out));
    addSubcommand(_GraphFindCommand(out));
    addSubcommand(_GraphPathCommand(out));
    addSubcommand(_GraphShowCommand(out));
  }
  @override
  String get name => 'graph';
  @override
  String get description =>
      'Query and render the graph (stats/find/path/show).';
}

class _GraphStatsCommand extends _Base {
  _GraphStatsCommand(super.out);
  @override
  String get name => 'stats';
  @override
  String get description => 'Counts, orphans, and per-module node counts.';

  @override
  Future<int> run() async {
    final dir = requirePositional('graph stats <qa_graph>');
    if (dir == null) {
      return 64;
    }
    final graph = _load(dir, out);
    if (graph == null) {
      return 1;
    }
    final edges = graph.nodes.fold<int>(
      0,
      (sum, node) => sum + node.payload.edges.length,
    );
    final perModule = <String, int>{};
    for (final node in graph.nodes) {
      final module =
          node.id.contains('.') ? node.id.split('.').first : '(root)';
      perModule[module] = (perModule[module] ?? 0) + 1;
    }
    final orphans = _unreachable(graph);

    out
      ..writeln('nodes:   ${graph.nodes.length}')
      ..writeln('edges:   $edges')
      ..writeln('entries: ${graph.entryNodeIds.join(', ')}')
      ..writeln('orphans: ${orphans.isEmpty ? 'none' : orphans.join(', ')}')
      ..writeln('modules:');
    final modules = perModule.keys.toList()..sort();
    for (final module in modules) {
      out.writeln('  $module: ${perModule[module]}');
    }
    return 0;
  }
}

class _GraphFindCommand extends _Base {
  _GraphFindCommand(super.out) {
    argParser
      ..addOption('tag')
      ..addOption('owner');
  }
  @override
  String get name => 'find';
  @override
  String get description => 'Find nodes by --tag and/or --owner.';

  @override
  Future<int> run() async {
    final dir = requirePositional('graph find <qa_graph> [--tag] [--owner]');
    if (dir == null) {
      return 64;
    }
    final graph = _load(dir, out);
    if (graph == null) {
      return 1;
    }
    final tag = argResults!.option('tag');
    final owner = argResults!.option('owner');
    final matches = graph.nodes
        .where((node) {
          final tagOk = tag == null || node.payload.tags.contains(tag);
          final ownerOk = owner == null || node.payload.owner == owner;
          return tagOk && ownerOk;
        })
        .map((node) => node.id)
        .toList()
      ..sort();
    for (final id in matches) {
      out.writeln(id);
    }
    out.writeln('${matches.length} match(es)');
    return 0;
  }
}

class _GraphPathCommand extends _Base {
  _GraphPathCommand(super.out);
  @override
  String get name => 'path';
  @override
  String get description => 'Show a shortest path between two nodes.';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.length < 3) {
      out.writeln('usage: applens graph path <qa_graph> <from> <to>');
      return 64;
    }
    final graph = _load(rest[0], out);
    if (graph == null) {
      return 1;
    }
    final path = _shortestPath(graph, rest[1], rest[2]);
    if (path == null) {
      out.writeln('no path from ${rest[1]} to ${rest[2]}');
      return 1;
    }
    out.writeln(path.join(' -> '));
    return 0;
  }
}

class _GraphShowCommand extends _Base {
  _GraphShowCommand(super.out) {
    argParser.addOption('out', help: 'Write the rendered HTML to this file.');
  }
  @override
  String get name => 'show';
  @override
  String get description => 'Render a module subgraph to an HTML file.';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.length < 2) {
      out.writeln('usage: applens graph show <qa_graph> <module> [--out]');
      return 64;
    }
    final graph = _load(rest[0], out);
    if (graph == null) {
      return 1;
    }
    final svg = renderModule(graph, rest[1]);
    final html = '<!doctype html><meta charset="utf-8"><body>$svg</body>';
    final outPath = argResults!.option('out') ?? 'graph_${rest[1]}.html';
    File(outPath).writeAsStringSync(html);
    out.writeln(style.ok('✓ wrote $outPath'));
    return 0;
  }
}

List<String> _unreachable(Graph graph) {
  final reachable = <String>{};
  final queue = [...graph.entryNodeIds.where(graph.byId.containsKey)];
  reachable.addAll(queue);
  while (queue.isNotEmpty) {
    final node = graph.byId[queue.removeLast()]!;
    for (final edge in node.payload.edges) {
      if (graph.byId.containsKey(edge.target) && reachable.add(edge.target)) {
        queue.add(edge.target);
      }
    }
  }
  return graph.nodes
      .map((n) => n.id)
      .where((id) => !reachable.contains(id))
      .toList()
    ..sort();
}

List<String>? _shortestPath(Graph graph, String from, String to) {
  if (!graph.byId.containsKey(from) || !graph.byId.containsKey(to)) {
    return null;
  }
  final parent = <String, String?>{from: null};
  final queue = <String>[from];
  while (queue.isNotEmpty) {
    final current = queue.removeAt(0);
    if (current == to) {
      final path = <String>[];
      String? node = to;
      while (node != null) {
        path.add(node);
        node = parent[node];
      }
      return path.reversed.toList();
    }
    for (final edge in graph.byId[current]!.payload.edges) {
      if (graph.byId.containsKey(edge.target) &&
          !parent.containsKey(edge.target)) {
        parent[edge.target] = current;
        queue.add(edge.target);
      }
    }
  }
  return null;
}
