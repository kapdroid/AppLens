// AppLens baseline-record host for the stranger app.
//
// Runs on a device via `applens run qa_graph
//   --entrypoint integration_test/applens_record_entry.dart -d <device>`.
// Captures the visual-tagged screen and reports the PNG to the host, where the
// flutter-drive driver content-addresses it into build/applens/goldens/. Uses
// only AppLens's public API (the stranger-app rule).
import 'dart:convert';

import 'package:applens_runner/applens_runner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:stranger_app/cart_model.dart';
import 'package:stranger_app/main.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('AppLens records the stranger baselines', (tester) async {
    await tester.pumpWidget(StrangerApp(cart: CartModel()));
    await tester.pumpAndSettle();

    final driver = appLensWidgetDriver(tester);
    // shop.dashboard is the entry route — full-screen scope, no navigation.
    // On the device's live binding capture needs no runAsync wrapper.
    final capture = await driver.capture(const FullScreenScope());

    binding.reportData = <String, dynamic>{
      'baselines': [
        {
          'node': 'shop.dashboard',
          'image': baselineImageKey(capture.pngBytes),
          'kind': 'full_screen',
          'png_b64': base64Encode(capture.pngBytes),
        },
      ],
    };
  });
}
