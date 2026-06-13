import 'package:applens_compare/applens_compare.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('default comparator thresholds match the spec', () {
    expect(defaultDiffRatioThreshold, 0.001);
    expect(defaultYiqThreshold, 0.1);
  });
}
