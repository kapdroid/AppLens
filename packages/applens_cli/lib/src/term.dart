import 'dart:io';

/// Hand-rolled ANSI styler for CLI output — no dependency. Each method colors
/// its argument only when [ansi] is true; otherwise it returns the string
/// unchanged, so output stays plain in pipes, CI, `NO_COLOR`, and tests (which
/// inject a `StringBuffer`, never `stdout`).
class Style {
  const Style(this.ansi);

  /// Whether to emit ANSI escape codes.
  final bool ansi;

  String ok(String s) => _wrap(s, '32'); // green
  String fail(String s) => _wrap(s, '31'); // red
  String warn(String s) => _wrap(s, '33'); // yellow
  String step(String s) => _wrap(s, '36;1'); // bold cyan
  String dim(String s) => _wrap(s, '90'); // gray
  String bold(String s) => _wrap(s, '1');

  String _wrap(String s, String code) => ansi ? '\x1B[${code}m$s\x1B[0m' : s;

  /// Decides whether color suits [out]: only when it is the real [stdout],
  /// attached to an ANSI-capable terminal, with `NO_COLOR` unset and
  /// `--no-color` not passed. Any injected sink (a test's `StringBuffer`) →
  /// `false`, which keeps every headless test's output plain.
  static Style forSink(StringSink out, {bool noColorFlag = false}) {
    final ansi = identical(out, stdout) &&
        stdout.hasTerminal &&
        stdout.supportsAnsiEscapes &&
        Platform.environment['NO_COLOR'] == null &&
        !noColorFlag;
    return Style(ansi);
  }
}
