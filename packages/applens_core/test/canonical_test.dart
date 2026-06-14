import 'package:applens_core/src/util/canonical.dart';
import 'package:test/test.dart';

void main() {
  test('canonicalize keeps values stored under non-String keys', () {
    final result = canonicalize({2: 'b', 1: 'a'}) as Map;
    // Re-looking-up by the stringified key used to miss non-String keys and
    // yield null, silently dropping the value.
    expect(result['1'], 'a');
    expect(result['2'], 'b');
  });

  test('contentHash distinguishes data differing only under a non-String key',
      () {
    final h1 = contentHash({
      'm': {1: 'a', 2: 'b'}
    });
    final h2 = contentHash({
      'm': {1: 'DIFFERENT', 2: 'b'}
    });
    expect(h1, isNot(h2));
  });

  test('canonicalJson is stable across String-key ordering', () {
    expect(canonicalJson({'b': 1, 'a': 2}), canonicalJson({'a': 2, 'b': 1}));
  });

  test('list order is preserved (it is semantically significant)', () {
    expect(canonicalize([3, 1, 2]), [3, 1, 2]);
  });
}
