import 'dart:io';

import 'package:applens_compare/applens_compare.dart';
import 'package:applens_core/applens_core.dart';
import 'package:applens_runner/applens_runner.dart';
import 'package:applens_runner/src/driver/applens_driver.dart';
import 'package:applens_runner/src/visual/capture_scope.dart';
import 'package:applens_runner/src/visual/visual_tier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _screen(Color color) => MaterialApp(
      debugShowCheckedModeBanner: false,
      home: ColoredBox(color: color),
    );

void main() {
  // The whole Session-7 tier-3 path end to end on the automated binding:
  // capture → record golden → load → compare green, then a UI change → red
  // diff. The emulator gate is then only a device-DPR confirmation of this.
  testWidgets('record a baseline, match it green, catch a colour regression',
      (tester) async {
    const context =
        BaselineContext(device: 'host', locale: 'en', theme: 'light');
    final dir = Directory.systemTemp.createTempSync('applens_e2e');
    addTearDown(() => dir.deleteSync(recursive: true));

    final driver = AppLensWidgetDriver(tester);
    const scope = FullScreenScope();

    // 1. Record the baseline from the current screen.
    await tester.pumpWidget(_screen(const Color(0xFF2244AA)));
    final baselineCapture =
        (await tester.runAsync(() => driver.capture(scope)))!;
    final recorded = await recordBaselines(
      captures: {'home': baselineCapture},
      kinds: {'home': captureKindOf(scope)},
      context: context,
      goldensDir: dir.path,
    );
    final baseline = recorded.single.baseline;
    expect(baseline.capture, CaptureKind.fullScreen);
    expect(baseline.image, startsWith('sha256:'));

    final source = IoBaselineSource(dir.path);

    // 2. Re-capture the unchanged screen → tier 3 matches (green).
    await tester.pumpWidget(_screen(const Color(0xFF2244AA)));
    final unchanged = (await tester.runAsync(() => driver.capture(scope)))!;
    final green = evaluateTier3(
      actual: unchanged,
      baselinePng: await source.load(baseline),
    );
    expect(green.assertion.passed, isTrue);
    expect(green.diffPng, isNull);

    // 3. Change the colour → tier 3 fails with a red diff overlay.
    await tester.pumpWidget(_screen(const Color(0xFFCC0000)));
    final changed = (await tester.runAsync(() => driver.capture(scope)))!;
    final red = evaluateTier3(
      actual: changed,
      baselinePng: await source.load(baseline),
      comparator: const VisualComparator(diffRatioThreshold: 0),
    );
    expect(red.assertion.passed, isFalse);
    expect(red.diffPng, isNotNull);
  });
}
