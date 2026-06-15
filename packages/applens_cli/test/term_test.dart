import 'package:applens_cli/src/term.dart';
import 'package:test/test.dart';

void main() {
  group('Style', () {
    test('ansi:false returns plain strings (no escape codes)', () {
      const s = Style(false);
      expect(s.ok('✓ wrote'), '✓ wrote');
      expect(s.fail('x'), 'x');
      expect(s.step('y'), 'y');
      expect(s.dim('z').contains('\x1B'), isFalse);
    });

    test('ansi:true wraps in ANSI escape codes around the text', () {
      const s = Style(true);
      final out = s.ok('hi');
      expect(out, contains('\x1B['));
      expect(out, contains('hi'));
      expect(out, endsWith('\x1B[0m'));
    });

    test('forSink on an injected StringBuffer is never colored', () {
      // The guarantee that keeps every headless test plain: a sink that is not
      // stdout can never be colored, regardless of the real terminal.
      expect(Style.forSink(StringBuffer()).ansi, isFalse);
    });

    test('forSink honors the --no-color flag', () {
      expect(Style.forSink(StringBuffer(), noColorFlag: true).ansi, isFalse);
    });
  });
}
