import '../util/source_location.dart';

/// How serious a [Diagnostic] is. Only [Severity.error] fails `validate`.
enum Severity { error, warning, info }

/// A single finding from validation: a stable [code] (for tests and tooling), a
/// human [message], and an optional [location] so a failure points straight at
/// the offending file (ARCHITECTURE.md §5).
class Diagnostic {
  const Diagnostic(this.severity, this.code, this.message, {this.location});

  final Severity severity;
  final String code;
  final String message;
  final SourceLocation? location;

  bool get isError => severity == Severity.error;

  @override
  String toString() {
    final prefix = location == null ? '' : '$location: ';
    return '$prefix${severity.name}[$code]: $message';
  }
}
