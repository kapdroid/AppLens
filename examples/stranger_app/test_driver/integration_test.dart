// Host-side driver for `flutter drive`. Receives whatever the on-device
// entrypoint reports (binding.reportData) and writes it under build/applens for
// `applens report` / baseline recording to consume off-device — the canonical
// data path (no adb pull, no on-device SQLite).
import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(
      responseDataCallback: (data) async {
        // A walk: the run record → run.json (for `applens report`).
        final run = data?['run'];
        if (run != null) {
          File('build/applens/run.json')
            ..parent.createSync(recursive: true)
            ..writeAsStringSync(jsonEncode(run));
        }

        // A baseline-record pass: each captured PNG → a content-addressed
        // golden, plus a manifest of the VisualBaseline entries to add to the
        // graph (the human reviews and commits — baselines flow through a PR).
        final baselines = data?['baselines'];
        if (baselines is List) {
          final manifest = <Map<String, dynamic>>[];
          for (final entry in baselines.cast<Map<dynamic, dynamic>>()) {
            final image = entry['image'] as String; // sha256:<hex>
            final hex = image.substring('sha256:'.length);
            File('build/applens/goldens/$hex.png')
              ..parent.createSync(recursive: true)
              ..writeAsBytesSync(base64Decode(entry['png_b64'] as String));
            manifest.add({
              'node': entry['node'],
              'image': image,
              'kind': entry['kind'],
            });
          }
          File('build/applens/baselines.manifest.json')
            ..parent.createSync(recursive: true)
            ..writeAsStringSync(jsonEncode(manifest));
        }

        // A structural-record pass: each captured semantic snapshot →
        // structural/<hex>.json, plus a manifest of node → snapshot ref to add
        // to the graph (reviewed and committed via PR, like goldens).
        final structural = data?['structural'];
        if (structural is String) {
          final entries =
              (jsonDecode(structural) as List).cast<Map<String, dynamic>>();
          final manifest = <Map<String, dynamic>>[];
          for (final entry in entries) {
            final key = entry['key'] as String; // sha256:<hex>
            final hex = key.substring('sha256:'.length);
            File('build/applens/structural/$hex.json')
              ..parent.createSync(recursive: true)
              ..writeAsStringSync(jsonEncode(entry['snapshot']));
            manifest.add({'node': entry['node'], 'snapshot': key});
          }
          File('build/applens/structural.manifest.json')
            ..parent.createSync(recursive: true)
            ..writeAsStringSync(jsonEncode(manifest));
        }
      },
    );
