// Host-side driver for `flutter drive`: receives the run record the on-device
// entrypoint reports (binding.reportData) and writes it to build/applens/run.json
// for `applens report` to render — the canonical off-device data path.
import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(
      responseDataCallback: (data) async {
        final run = data?['run'];
        if (run != null) {
          final file = File('build/applens/run.json');
          file.parent.createSync(recursive: true);
          file.writeAsStringSync(jsonEncode(run));
        }
      },
    );
