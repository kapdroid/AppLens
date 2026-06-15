import 'dart:convert';
import 'dart:io';

import 'package:applens_core/applens_core.dart';

import 'term.dart';

/// A connected device/emulator the shell can target.
class DeviceInfo {
  const DeviceInfo(this.id, this.name);
  final String id;
  final String name;
}

/// Reads one line for [prompt] (prod: print + `stdin.readLineSync()`; tests
/// inject a scripted queue). Returns null on EOF.
typedef Reader = String? Function(String prompt);

/// Lists connected devices (prod: `flutter devices --machine`; tests fake it).
typedef DeviceLister = Future<List<DeviceInfo>> Function();

/// Runs a full `applens` arg vector through the one-shot CommandRunner.
typedef Dispatcher = Future<int> Function(List<String> args);

/// The interactive AppLens session: a persistent shell where bare-word commands
/// run against a remembered context (graph dir + device), reusing every CLI
/// command via [dispatch]. The line-handling core, [handle], is unit-testable
/// with an injected sink, reader, device lister, and dispatcher — no TTY needed.
class Shell {
  Shell({
    required this.out,
    required this.style,
    required this.dispatch,
    Reader? reader,
    DeviceLister? deviceLister,
    this.graphDir,
  })  : reader = reader ?? _stdinReader,
        deviceLister = deviceLister ?? detectDevices;

  final StringSink out;
  final Style style;
  final Dispatcher dispatch;
  final Reader reader;
  final DeviceLister deviceLister;

  String? graphDir;
  String? device;
  String? lastReport;
  String? lastVerdict;

  /// The bare-word commands that route to a CLI subcommand.
  static const _commands = {
    'validate', 'plan', 'run', 'all', 'report', 'graph', //
    'approve', 'triage', 'author', 'crawl', 'init',
  };

  /// The blocking read-eval loop. Returns 0 when the session ends.
  Future<int> repl() async {
    _printBanner();
    graphDir ??= Directory('qa_graph').existsSync() ? 'qa_graph' : null;
    await _startupDetect();
    _printStatus();
    while (true) {
      final line = reader(style.step('applens ❯ '));
      if (line == null) {
        break; // EOF / Ctrl-D
      }
      if (!await handle(line)) {
        break;
      }
    }
    out.writeln('bye');
    return 0;
  }

  /// Processes ONE input line. Returns false to quit the session.
  Future<bool> handle(String line) async {
    final tokens = _tokenize(line);
    if (tokens.isEmpty) {
      return true;
    }
    final cmd = tokens.first;
    final rest = tokens.sublist(1);
    switch (cmd) {
      case 'exit':
      case 'quit':
        return false;
      case 'help':
        _printHelp();
      case 'status':
        _printStatus();
      case 'clear':
        if (style.ansi) {
          out.write('\x1B[2J\x1B[H');
        }
      case 'use':
        if (rest.isEmpty) {
          out.writeln(style.fail('usage: use <qa_graph-dir>'));
        } else {
          graphDir = rest.first;
          out.writeln(style.ok('graph set to ${rest.first}'));
        }
      case 'devices':
        await _listDevices();
      case 'device':
        await _setDevice(rest);
      case 'open':
        await _openLast();
      default:
        await _dispatchCommand(cmd, rest);
    }
    return true;
  }

  Future<void> _dispatchCommand(String cmd, List<String> rest) async {
    if (!_commands.contains(cmd)) {
      out.writeln(style.fail('unknown command "$cmd" — type help'));
      return;
    }
    final args = await _buildArgs(cmd, rest);
    if (args == null) {
      return; // a hint was already printed
    }
    final code = await dispatch(args);
    if (cmd == 'all') {
      lastReport = 'build/applens/report.html';
      lastVerdict = code == 0 ? 'GREEN' : (code == 2 ? 'PENDING' : 'RED');
    }
  }

  /// Rewrites a bare-word command into a full arg vector using the session
  /// context: splices the graph dir as the leading positional, defaults the run
  /// record, and resolves a device for the commands that walk one. Returns null
  /// (after a hint) when required context is missing.
  Future<List<String>?> _buildArgs(String cmd, List<String> rest) async {
    switch (cmd) {
      case 'validate':
      case 'plan':
        final dir = _requireGraph();
        return dir == null ? null : [cmd, dir, ...rest];
      case 'run':
      case 'all':
        final dir = _requireGraph();
        if (dir == null) {
          return null;
        }
        final dev = await _ensureDevice();
        return dev == null ? null : [cmd, dir, ...rest, '--device', dev];
      case 'crawl':
        final dev = await _ensureDevice();
        return dev == null ? null : [cmd, ...rest, '--device', dev];
      case 'report':
      case 'triage':
      case 'approve':
        final dir = _requireGraph();
        if (dir == null) {
          return null;
        }
        return [cmd, dir, 'build/applens/run.json', ...rest];
      case 'graph':
        if (rest.isEmpty) {
          out.writeln(style.fail('usage: graph <stats|find|path|show> ...'));
          return null;
        }
        final dir = _requireGraph();
        if (dir == null) {
          return null;
        }
        return ['graph', rest.first, dir, ...rest.sublist(1)];
      default: // author, init — no graph positional
        return [cmd, ...rest];
    }
  }

  String? _requireGraph() {
    if (graphDir == null) {
      out.writeln(style.fail(
          'no graph loaded — type `use qa_graph` (or run from a dir with one)'));
    }
    return graphDir;
  }

  // --- Device discovery & selection -----------------------------------------

  /// Resolves a usable device on demand: reuses the held one if still attached,
  /// auto-selects when exactly one is connected, prompts when several are, and
  /// returns null (after a message) when none are or the user cancels.
  Future<String?> _ensureDevice() async {
    final devices = await deviceLister();
    if (device != null && !devices.any((d) => d.id == device)) {
      out.writeln(style.warn('device $device is no longer connected'));
      device = null;
    }
    if (device != null) {
      return device;
    }
    if (devices.isEmpty) {
      out.writeln(style.fail('✗ no device/emulator connected — boot one '
          '(e.g. `flutter emulators --launch <id>`) and try again'));
      return null;
    }
    if (devices.length == 1) {
      device = devices.first.id;
      out.writeln(
          style.ok('using ${devices.first.name} (${devices.first.id})'));
      return device;
    }
    _printDeviceList(devices);
    final pick = reader('select device [1-${devices.length}]: ');
    final index = int.tryParse(pick?.trim() ?? '');
    if (index == null || index < 1 || index > devices.length) {
      out.writeln(style.warn('cancelled — no device selected'));
      return null;
    }
    final chosen = devices[index - 1];
    device = chosen.id;
    out.writeln(style.ok('using ${chosen.name} (${chosen.id})'));
    return device;
  }

  Future<void> _startupDetect() async {
    final devices = await deviceLister();
    if (devices.length == 1) {
      device = devices.first.id;
    }
  }

  Future<void> _listDevices() async {
    final devices = await deviceLister();
    if (devices.isEmpty) {
      out.writeln(style.warn('no devices connected'));
      return;
    }
    _printDeviceList(devices);
  }

  void _printDeviceList(List<DeviceInfo> devices) {
    for (var i = 0; i < devices.length; i++) {
      final marker = devices[i].id == device ? '*' : ' ';
      out.writeln('  $marker ${i + 1}. ${devices[i].name} (${devices[i].id})');
    }
  }

  Future<void> _setDevice(List<String> rest) async {
    if (rest.isEmpty) {
      await _ensureDevice();
      return;
    }
    device = rest.first;
    out.writeln(style.ok('device set to ${rest.first}'));
  }

  Future<void> _openLast() async {
    final path = lastReport ?? 'build/applens/report.html';
    if (!File(path).existsSync()) {
      out.writeln(style.warn('no report yet at $path — run `all` first'));
      return;
    }
    await openInBrowser(path, out, style);
  }

  // --- Presentation ----------------------------------------------------------

  void _printBanner() {
    out
      ..writeln(style.bold('AppLens') +
          style.dim('  ·  graph-based QA for '
              'Flutter'))
      ..writeln(style.dim('bare-word commands; type `help`, or `exit` to '
          'quit'));
  }

  void _printStatus() {
    final graph = graphDir == null
        ? style.dim('(none — type `use qa_graph`)')
        : '$graphDir${_nodeCountSuffix()}';
    final dev = device ?? style.dim('(none — will prompt when needed)');
    out.writeln(style.dim('graph: ') +
        graph +
        style.dim('  ·  device: ') +
        dev +
        (lastVerdict == null
            ? ''
            : style.dim('  ·  last: ') + _verdictColored(lastVerdict!)));
  }

  String _nodeCountSuffix() {
    try {
      final count = loadGraph(graphDir!).nodes.length;
      return ' ($count nodes)';
    } on Object {
      return '';
    }
  }

  String _verdictColored(String v) => switch (v) {
        'GREEN' => style.ok(v),
        'PENDING' => style.warn(v),
        _ => style.fail(v),
      };

  void _printHelp() {
    out
      ..writeln(style.bold('commands'))
      ..writeln('  ${style.step('all')}        walk on a device → report → open'
          ' (the one-shot pipeline)')
      ..writeln('  ${style.step('run')}        walk only (writes run.json)')
      ..writeln('  ${style.step('validate')}   check the graph')
      ..writeln('  ${style.step('plan')}       compile a plan '
          '(--strategy smoke|regression|impact|soak)')
      ..writeln('  ${style.step('report')}     render the last run\'s report')
      ..writeln('  ${style.step('approve')}    --node <id>  promote a drift to '
          'the baseline')
      ..writeln('  ${style.step('graph')}      stats | find | path | show')
      ..writeln('  ${style.step('triage')} ${style.step('author')} '
          '${style.step('crawl')} ${style.step('init')}')
      ..writeln(style.bold('session'))
      ..writeln('  ${style.step('use')} <dir>  set the graph    '
          '${style.step('device')} [id] / ${style.step('devices')}  pick/list '
          'a device')
      ..writeln('  ${style.step('status')}     show context     '
          '${style.step('open')}  open the last report')
      ..writeln('  ${style.step('clear')}      clear screen     '
          '${style.step('exit')}  quit');
  }

  List<String> _tokenize(String line) =>
      line.trim().split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
}

String? _stdinReader(String prompt) {
  stdout.write(prompt);
  return stdin.readLineSync();
}

/// Detects connected devices via `flutter devices --machine` (JSON). Returns an
/// empty list on any error so the shell degrades to "none connected".
Future<List<DeviceInfo>> detectDevices() async {
  try {
    final result = await Process.run('flutter', ['devices', '--machine']);
    if (result.exitCode != 0) {
      return const [];
    }
    final decoded = jsonDecode(result.stdout as String);
    if (decoded is! List) {
      return const [];
    }
    return [
      for (final entry in decoded)
        if (entry is Map && entry['id'] != null)
          DeviceInfo('${entry['id']}', '${entry['name'] ?? entry['id']}'),
    ];
  } on Exception {
    return const [];
  }
}

/// Opens [path] in the OS default app (the browser for the HTML report).
/// Failures are non-fatal — a warning, never a crash.
Future<void> openInBrowser(String path, StringSink out, Style style) async {
  final (cmd, args) = Platform.isMacOS
      ? ('open', [path])
      : Platform.isWindows
          ? ('cmd', ['/c', 'start', '', path])
          : ('xdg-open', [path]);
  try {
    final result = await Process.run(cmd, args);
    if (result.exitCode != 0) {
      out.writeln(style.warn('⚠ could not open $path (exit ${result.exitCode})'
          ' — open it manually'));
    }
  } on ProcessException {
    out.writeln(style.warn('⚠ could not open $path — open it manually'));
  }
}
