import 'dart:io';

import 'package:applens_cli/src/shell.dart';
import 'package:applens_cli/src/term.dart';
import 'package:test/test.dart';

String _repoQaGraph() {
  var dir = Directory.current;
  while (true) {
    final candidate = '${dir.path}/examples/stranger_app/qa_graph';
    if (Directory(candidate).existsSync()) return candidate;
    final parent = dir.parent;
    if (parent.path == dir.path) throw StateError('qa_graph not found');
    dir = parent;
  }
}

/// A headless harness: records dispatched arg vectors, scripts reader input,
/// and fakes the device list — so the shell's logic is tested without a TTY.
class _Harness {
  final out = StringBuffer();
  final dispatched = <List<String>>[];
  final inputs = <String>[];
  List<DeviceInfo> devices = const [];
  int dispatchCode = 0;

  Shell build({String? graphDir}) => Shell(
        out: out,
        style: const Style(false),
        dispatch: (args) async {
          dispatched.add(args);
          return dispatchCode;
        },
        reader: (prompt) => inputs.isEmpty ? null : inputs.removeAt(0),
        deviceLister: () async => devices,
        graphDir: graphDir,
      );
}

void main() {
  group('built-ins', () {
    test('help lists the headline commands', () async {
      final h = _Harness();
      await h.build().handle('help');
      expect(h.out.toString(), contains('all'));
      expect(h.out.toString(), contains('validate'));
      expect(h.out.toString(), contains('device'));
    });

    test('exit quits the session', () async {
      expect(await _Harness().build().handle('exit'), isFalse);
    });

    test('an empty line is a no-op that keeps the session', () async {
      final h = _Harness();
      expect(await h.build().handle('   '), isTrue);
      expect(h.dispatched, isEmpty);
    });

    test('use sets the graph and status shows its node count', () async {
      final h = _Harness();
      final shell = h.build();
      await shell.handle('use ${_repoQaGraph()}');
      h.out.clear();
      await shell.handle('status');
      expect(h.out.toString(), contains(_repoQaGraph()));
      expect(h.out.toString(), contains('nodes'));
    });

    test('an unknown command is a friendly error, not a dispatch', () async {
      final h = _Harness();
      await h.build(graphDir: 'qa_graph').handle('frobnicate');
      expect(h.out.toString(), contains('unknown command'));
      expect(h.dispatched, isEmpty);
    });
  });

  group('context injection', () {
    test('validate splices in the held graph dir', () async {
      final h = _Harness();
      await h.build(graphDir: 'qa_graph').handle('validate');
      expect(h.dispatched.single, ['validate', 'qa_graph']);
    });

    test('a graph command with no graph loaded prints a hint, no dispatch',
        () async {
      final h = _Harness();
      await h.build().handle('validate');
      expect(h.out.toString(), contains('no graph loaded'));
      expect(h.dispatched, isEmpty);
    });

    test('report defaults the run.json after the graph dir', () async {
      final h = _Harness();
      await h.build(graphDir: 'qa_graph').handle('report');
      expect(h.dispatched.single,
          ['report', 'qa_graph', 'build/applens/run.json']);
    });

    test('graph stats splices the dir after the subcommand', () async {
      final h = _Harness();
      await h.build(graphDir: 'qa_graph').handle('graph stats');
      expect(h.dispatched.single, ['graph', 'stats', 'qa_graph']);
    });
  });

  group('device discovery', () {
    test('no device connected → message, no dispatch', () async {
      final h = _Harness()..devices = const [];
      await h.build(graphDir: 'qa_graph').handle('all');
      expect(h.out.toString(), contains('no device'));
      expect(h.dispatched, isEmpty);
    });

    test('exactly one device → auto-used, appended to the args', () async {
      final h = _Harness()
        ..devices = const [DeviceInfo('emulator-5554', 'Pixel')];
      await h.build(graphDir: 'qa_graph').handle('all');
      expect(h.dispatched.single,
          ['all', 'qa_graph', '--device', 'emulator-5554']);
    });

    test('several devices → prompt, and the pick is used', () async {
      final h = _Harness()
        ..devices = const [DeviceInfo('a', 'A'), DeviceInfo('b', 'B')]
        ..inputs.add('2');
      await h.build(graphDir: 'qa_graph').handle('run');
      expect(h.dispatched.single, ['run', 'qa_graph', '--device', 'b']);
    });

    test('several devices → an invalid pick cancels, no dispatch', () async {
      final h = _Harness()
        ..devices = const [DeviceInfo('a', 'A'), DeviceInfo('b', 'B')]
        ..inputs.add('');
      await h.build(graphDir: 'qa_graph').handle('all');
      expect(h.out.toString(), contains('cancelled'));
      expect(h.dispatched, isEmpty);
    });

    test('a held device that detached is cleared and re-resolved', () async {
      final h = _Harness()..devices = const [DeviceInfo('a', 'A')];
      final shell = h.build(graphDir: 'qa_graph')..device = 'gone';
      await shell.handle('run');
      expect(h.out.toString(), contains('no longer connected'));
      expect(h.dispatched.single, ['run', 'qa_graph', '--device', 'a']);
    });

    test('crawl appends the device with no graph positional', () async {
      final h = _Harness()..devices = const [DeviceInfo('a', 'A')];
      await h.build(graphDir: 'qa_graph').handle('crawl --module shop');
      expect(
          h.dispatched.single, ['crawl', '--module', 'shop', '--device', 'a']);
    });
  });
}
