import 'dart:io';
import 'dart:typed_data';

import 'package:applens_core/applens_core.dart';
import 'package:applens_runner/applens_runner.dart';
import 'package:flutter_test/flutter_test.dart';

VisualBaseline _baselineFor(String image) => VisualBaseline(
      context:
          const BaselineContext(device: 'host', locale: 'en', theme: 'light'),
      capture: CaptureKind.fullScreen,
      state: BaselineState.approved,
      image: image,
    );

void main() {
  final png = Uint8List.fromList([137, 80, 78, 71, 1, 2, 3, 4]);

  test('baselineImageKey is a deterministic content address', () {
    final key = baselineImageKey(png);
    expect(key, startsWith('sha256:'));
    expect(baselineImageKey(png), key);
    expect(
      baselineImageKey(Uint8List.fromList([...png, 9])),
      isNot(key),
    );
  });

  group('IoBaselineSource', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('applens_goldens'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('loads the content-addressed golden for a baseline', () async {
      final key = baselineImageKey(png);
      File('${dir.path}/${key.substring('sha256:'.length)}.png')
          .writeAsBytesSync(png);

      final source = IoBaselineSource(dir.path);
      expect(await source.load(_baselineFor(key)), equals(png));
    });

    test('returns null when the golden is absent', () async {
      final source = IoBaselineSource(dir.path);
      expect(await source.load(_baselineFor('sha256:deadbeef')), isNull);
    });

    test('returns null for a baseline with no/!sha256 image', () async {
      final source = IoBaselineSource(dir.path);
      expect(await source.load(_baselineFor('not-a-hash')), isNull);
    });
  });

  group('MapBaselineSource', () {
    test('loads bundled goldens by key, null when absent', () async {
      final key = baselineImageKey(png);
      final source = MapBaselineSource({key: png});
      expect(await source.load(_baselineFor(key)), equals(png));
      expect(await source.load(_baselineFor('sha256:other')), isNull);
    });
  });
}
