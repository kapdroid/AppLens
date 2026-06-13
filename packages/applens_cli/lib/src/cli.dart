import 'dart:io';

import 'package:applens_core/applens_core.dart';
import 'package:applens_report/applens_report.dart';
import 'package:args/command_runner.dart';
import 'package:yaml/yaml.dart';

import 'templates.dart';

/// The AppLens command-line entrypoint. Output is injected so commands are
/// testable headless; each command returns a process exit code.
class AppLensCli {
  AppLensCli({StringSink? out}) : _out = out ?? stdout;

  final StringSink _out;

  Future<int> run(List<String> args) async {
    final runner = CommandRunner<int>(
      'applens',
      'Graph-based autonomous QA for Flutter.',
    )
      ..addCommand(_ValidateCommand(_out))
      ..addCommand(_PlanCommand(_out))
      ..addCommand(_GraphCommand(_out))
      ..addCommand(_ReportCommand(_out))
      ..addCommand(_InitCommand(_out))
      ..addCommand(_RunCommand(_out));
    try {
      return await runner.run(args) ?? 0;
    } on UsageException catch (error) {
      _out.writeln(error.message);
      return 64;
    }
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

abstract class _Base extends Command<int> {
  _Base(this.out);
  final StringSink out;

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
          ? '✓ valid (${graph.nodes.length} nodes)'
          : '✗ $errors error(s)',
    );
    return errors == 0 ? 0 : 1;
  }
}

class _PlanCommand extends _Base {
  _PlanCommand(super.out) {
    argParser
      ..addOption('strategy', defaultsTo: 'smoke', help: 'smoke | regression')
      ..addOption('out', help: 'Write the plan YAML to this file.');
  }
  @override
  String get name => 'plan';
  @override
  String get description => 'Compile a test plan from a qa_graph directory.';

  @override
  Future<int> run() async {
    final dir = requirePositional('plan <qa_graph> [--strategy] [--out]');
    if (dir == null) {
      return 64;
    }
    final graph = _load(dir, out);
    if (graph == null) {
      return 1;
    }
    if (validateGraph(graph).any((d) => d.isError)) {
      out.writeln('✗ graph does not validate; fix it before planning');
      return 1;
    }
    final strategy = PlanStrategy.fromYaml(argResults!.option('strategy')!);
    if (strategy == null) {
      out.writeln('unknown strategy "${argResults!.option('strategy')}"');
      return 64;
    }
    final plan = compilePlan(graph, strategy: strategy);
    final yaml = writeYaml(plan.toMap());
    final outPath = argResults!.option('out');
    if (outPath == null) {
      out.write(yaml);
    } else {
      File(outPath).writeAsStringSync(yaml);
      out.writeln('✓ wrote $outPath');
    }
    return 0;
  }
}

class _ReportCommand extends _Base {
  _ReportCommand(super.out) {
    argParser
      ..addOption('run-id', defaultsTo: 'run')
      ..addOption('out', defaultsTo: 'applens_report.html');
  }
  @override
  String get name => 'report';
  @override
  String get description =>
      'Render an HTML report from a run store (exit 0/1/2).';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.length < 2) {
      out.writeln(
          'usage: applens report <qa_graph> <run.db> [--run-id] [--out]');
      return 64;
    }
    final graph = _load(rest[0], out);
    if (graph == null) {
      return 1;
    }
    final store = SqliteRunStore.open(rest[1]);
    final record = await store.loadRun(argResults!.option('run-id')!);
    await store.close();
    if (record == null) {
      out.writeln('no run "${argResults!.option('run-id')}" in ${rest[1]}');
      return 1;
    }
    final outPath = argResults!.option('out')!;
    File(outPath).writeAsStringSync(renderRunReport(record, graph));
    out.writeln('✓ wrote $outPath');
    return exitCodeForRun(record);
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
    out.writeln(
        '✓ initialized — edit the entrypoint import, then `applens run qa_graph`');
    return 0;
  }
}

class _RunCommand extends _Base {
  _RunCommand(super.out) {
    argParser
      ..addOption('strategy', defaultsTo: 'smoke')
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
    final config = _readConfig('$dir/applens.yaml');
    final entrypoint = argResults!.option('entrypoint')!;
    final device = argResults!.option('device');

    // Pre-grant permissions at session start (ARCHITECTURE.md §7/§10) so native
    // dialogs never appear. Android uses `adb pm grant` with the app id from
    // applens.yaml; iOS (`simctl privacy grant`) is part of the walking-skeleton
    // handoff, not yet wired.
    final grants = [
      for (final permission in config.permissions)
        ['shell', 'pm', 'grant', config.appId, permission],
    ];
    for (final grant in grants) {
      out.writeln('adb ${grant.join(' ')}');
    }
    final flutterArgs = [
      'test',
      entrypoint,
      if (device != null) ...['-d', device],
    ];
    out.writeln('flutter ${flutterArgs.join(' ')}');

    if (argResults!.flag('dry-run')) {
      return 0;
    }
    if (device == null) {
      out.writeln('✗ --device is required to run on an emulator/device');
      return 64;
    }
    for (final grant in grants) {
      await Process.run('adb', ['-s', device, ...grant]);
    }
    final result = await Process.run('flutter', flutterArgs);
    out
      ..writeln(result.stdout)
      ..writeln(result.stderr);
    return result.exitCode == 0 ? 0 : 1;
  }

  _RunConfig _readConfig(String path) {
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
}

class _RunConfig {
  const _RunConfig(this.appId, this.permissions);
  final String appId;
  final List<String> permissions;
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
    out.writeln('✓ wrote $outPath');
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
