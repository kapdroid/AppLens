/// Validates [value] against a minimal JSON-Schema subset — object / type /
/// required / properties / enum / nullable / array-items — which is all
/// AppLens's structured verdicts need (ARCHITECTURE.md §12). Returns a list of
/// human-readable errors keyed by JSON path; empty means valid. Structured
/// output (not free text) is what survives a provider swap, so every adapter
/// runs its result through this before returning.
List<String> validateAgainstSchema(
  Object? value,
  Map<String, Object?> schema, [
  String path = r'$',
]) {
  final errors = <String>[];
  final type = schema['type'];

  if (value == null) {
    if (schema['nullable'] != true && type != 'null') {
      errors.add('$path: expected $type, got null');
    }
    return errors;
  }

  final allowed = schema['enum'];
  if (allowed is List && !allowed.contains(value)) {
    errors.add('$path: "$value" is not one of $allowed');
  }

  switch (type) {
    case 'object':
      if (value is! Map) {
        errors.add('$path: expected object');
        break;
      }
      final required =
          (schema['required'] as List?)?.cast<String>() ?? const [];
      for (final key in required) {
        if (!value.containsKey(key)) {
          errors.add('$path.$key: required field missing');
        }
      }
      final properties = schema['properties'];
      if (properties is Map) {
        for (final entry in properties.entries) {
          final key = entry.key as String;
          final sub = entry.value;
          if (value.containsKey(key) && sub is Map) {
            errors.addAll(
              validateAgainstSchema(
                value[key],
                sub.cast<String, Object?>(),
                '$path.$key',
              ),
            );
          }
        }
      }
    case 'array':
      if (value is! List) {
        errors.add('$path: expected array');
        break;
      }
      final items = schema['items'];
      if (items is Map) {
        final itemSchema = items.cast<String, Object?>();
        for (var i = 0; i < value.length; i++) {
          errors
              .addAll(validateAgainstSchema(value[i], itemSchema, '$path[$i]'));
        }
      }
    case 'string':
      if (value is! String) {
        errors.add('$path: expected string');
      }
    case 'number':
      if (value is! num) {
        errors.add('$path: expected number');
      }
    case 'integer':
      if (value is! int) {
        errors.add('$path: expected integer');
      }
    case 'boolean':
      if (value is! bool) {
        errors.add('$path: expected boolean');
      }
  }
  return errors;
}
