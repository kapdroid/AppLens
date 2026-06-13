/// Emits block-style YAML from a plain map/list/scalar tree (a model's
/// `toMap()`). String scalars are double-quoted so output is always valid and
/// re-parses to the same model — the round-trip the build plan requires. It is
/// not a general YAML emitter; it serves AppLens's own canonical maps.
String writeYaml(Map<String, Object?> map) {
  final buffer = StringBuffer();
  _writeMap(buffer, map, 0);
  return buffer.toString();
}

void _writeMap(StringBuffer buffer, Map<String, Object?> map, int indent) {
  final pad = ' ' * indent;
  map.forEach((key, value) {
    buffer
      ..write(pad)
      ..write(_key(key))
      ..write(':');
    _writeValue(buffer, value, indent);
  });
}

void _writeValue(StringBuffer buffer, Object? value, int indent) {
  if (value is Map<String, Object?>) {
    if (value.isEmpty) {
      buffer.writeln(' {}');
    } else {
      buffer.writeln();
      _writeMap(buffer, value, indent + 2);
    }
    return;
  }
  if (value is List) {
    if (value.isEmpty) {
      buffer.writeln(' []');
    } else {
      buffer.writeln();
      _writeList(buffer, value, indent + 2);
    }
    return;
  }
  buffer
    ..write(' ')
    ..writeln(_scalar(value));
}

void _writeList(StringBuffer buffer, List<Object?> list, int indent) {
  final pad = ' ' * indent;
  for (final item in list) {
    if (item is Map<String, Object?>) {
      if (item.isEmpty) {
        buffer
          ..write(pad)
          ..writeln('- {}');
      } else {
        buffer
          ..write(pad)
          ..writeln('-');
        _writeMap(buffer, item, indent + 2);
      }
    } else if (item is List) {
      buffer
        ..write(pad)
        ..writeln('-');
      _writeList(buffer, item, indent + 2);
    } else {
      buffer
        ..write(pad)
        ..write('- ')
        ..writeln(_scalar(item));
    }
  }
}

final RegExp _plainKey = RegExp(r'^[A-Za-z0-9_.]+$');

String _key(String key) => _plainKey.hasMatch(key) ? key : _quote(key);

String _scalar(Object? value) {
  if (value is String) {
    return _quote(value);
  }
  if (value is bool) {
    return value ? 'true' : 'false';
  }
  if (value == null) {
    return 'null';
  }
  return '$value'; // num
}

String _quote(String value) {
  final escaped = value
      .replaceAll(r'\', r'\\')
      .replaceAll('"', r'\"')
      .replaceAll('\n', r'\n')
      .replaceAll('\r', r'\r')
      .replaceAll('\t', r'\t');
  return '"$escaped"';
}
