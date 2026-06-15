import 'package:applens_sdk/applens_sdk.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(AppLensState.reset);

  test('records flags in the string form FlagConstraint reads', () {
    AppLensState.setFlag('cart_count', 3);
    AppLensState.setFlag('journey.started', true);
    expect(AppLensState.flags['cart_count'], '3');
    expect(AppLensState.flags['journey.started'], 'true');
  });

  test('clearFlag and reset remove state (the seed hook)', () {
    AppLensState.setFlag('a', 1);
    AppLensState.setFlag('b', 2);
    AppLensState.clearFlag('a');
    expect(AppLensState.flags.containsKey('a'), isFalse);
    expect(AppLensState.flags['b'], '2');
    AppLensState.reset();
    expect(AppLensState.flags, isEmpty);
  });

  test('flags is an unmodifiable view', () {
    AppLensState.setFlag('x', 'y');
    expect(() => AppLensState.flags['z'] = 'w', throwsUnsupportedError);
  });
}
