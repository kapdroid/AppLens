/// A 1-based position in a source file, used for precise parse and validation
/// diagnostics. A failure that can point at `file:line:col` never makes a human
/// search (ARCHITECTURE.md §5).
class SourceLocation {
  const SourceLocation({
    required this.source,
    required this.line,
    required this.column,
  });

  /// File path or label the YAML came from.
  final String source;
  final int line;
  final int column;

  @override
  String toString() => '$source:$line:$column';
}
