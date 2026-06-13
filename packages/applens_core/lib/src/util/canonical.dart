import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Recursively canonicalizes [value] so equal data has one representation:
/// map keys are sorted; list order is preserved (it is semantically
/// significant). Used for content hashing and structural equality.
Object? canonicalize(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((key) => key.toString()).toList()..sort();
    return {for (final key in keys) key: canonicalize(value[key])};
  }
  if (value is Iterable) {
    return value.map(canonicalize).toList();
  }
  return value;
}

/// A deterministic JSON encoding of [value] with map keys sorted at every level.
String canonicalJson(Object? value) => jsonEncode(canonicalize(value));

/// Drops null values and empty collections from [map], so model `toMap()`
/// output (and the YAML serialized from it) stays free of empty noise and
/// round-trips consistently with parsers that default absent keys.
Map<String, Object?> compactMap(Map<String, Object?> map) {
  final result = <String, Object?>{};
  map.forEach((key, value) {
    if (value == null) {
      return;
    }
    if (value is Iterable && value.isEmpty) {
      return;
    }
    if (value is Map && value.isEmpty) {
      return;
    }
    result[key] = value;
  });
  return result;
}

/// A stable `sha256:<hex>` content hash of [value], independent of map-key
/// ordering. The same logical graph always hashes identically.
String contentHash(Object? value) {
  final digest = sha256.convert(utf8.encode(canonicalJson(value)));
  return 'sha256:$digest';
}
