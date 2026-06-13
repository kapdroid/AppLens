import 'dart:ui';

import 'package:applens_runner/applens_runner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('driver contract value types', () {
    test('selectors are sealed key/semantics variants', () {
      const WidgetSelector byKey = KeySelector('btn_place_order');
      const WidgetSelector bySemantics = SemanticsSelector('Place order');
      expect((byKey as KeySelector).key, 'btn_place_order');
      expect((bySemantics as SemanticsSelector).label, 'Place order');
    });

    test('SettlePolicy has sensible defaults', () {
      const policy = SettlePolicy();
      expect(policy.stableFrames, 2);
      expect(policy.keyboardUp, isFalse);
      expect(policy.timeout, const Duration(seconds: 10));
    });

    test('capture scopes cover full / widget / region', () {
      const scopes = <CaptureScope>[
        FullScreenScope(),
        WidgetScope(KeySelector('card_order_summary')),
        RegionScope(Rect.fromLTWH(0, 0, 10, 10)),
      ];
      expect(scopes, hasLength(3));
    });
  });

  group('oracle contract', () {
    test('OracleResult.passed reflects status', () {
      const ok = OracleResult(order: 10, status: OracleStatus.passed);
      const bad = OracleResult(
        order: 30,
        status: OracleStatus.failed,
        detail: 'pixel drift 0.4%',
      );
      expect(ok.passed, isTrue);
      expect(bad.passed, isFalse);
      expect(bad.detail, contains('drift'));
    });
  });
}
