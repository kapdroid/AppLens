import 'dart:typed_data';

import 'package:applens_llm/applens_llm.dart';
import 'package:test/test.dart';

const _schema = <String, Object?>{
  'type': 'object',
  'properties': {
    'verdict': {'type': 'string'},
  },
};

LlmRequest _request() => LlmRequest(
      messages: [
        const LlmMessage(LlmRole.system, 'You are AppLens triage.'),
        LlmMessage(
          LlmRole.user,
          'Tree diff: Button.color amber→blue. See the attached overlay.',
          images: [
            LlmImage(bytes: Uint8List.fromList([1, 2, 3]))
          ],
        ),
      ],
      jsonSchema: _schema,
      maxOutputTokens: 256,
    );

void main() {
  const vision =
      LlmCapabilities(vision: true, jsonMode: true, maxContextTokens: 1000);
  const noVision =
      LlmCapabilities(vision: false, jsonMode: true, maxContextTokens: 1000);

  test('a vision provider gets the request untouched', () {
    final request = _request();
    expect(identical(degradeForCapabilities(request, vision), request), isTrue);
  });

  test('a non-vision provider keeps the text tree-diff but drops images', () {
    final degraded = degradeForCapabilities(_request(), noVision);

    final user = degraded.messages.last;
    expect(user.text, contains('Tree diff'));
    expect(user.images, isEmpty);
    expect(degraded.messages.first.text, 'You are AppLens triage.');
    expect(degraded.jsonSchema, _schema);
    expect(degraded.maxOutputTokens, 256);
  });

  test('an image-only message is dropped rather than sent empty', () {
    final request = LlmRequest(
      messages: [
        LlmMessage(
          LlmRole.user,
          '',
          images: [
            LlmImage(bytes: Uint8List.fromList([9]))
          ],
        ),
      ],
      jsonSchema: _schema,
    );

    expect(degradeForCapabilities(request, noVision).messages, isEmpty);
  });

  test('degraded request sent to a no-vision fake provider carries no images',
      () async {
    final provider = FakeLlmProvider(
      const LlmResult(json: {'verdict': 'intended'}),
      capabilities: noVision,
    );

    final result = await provider
        .complete(degradeForCapabilities(_request(), provider.capabilities));

    expect(result.json['verdict'], 'intended');
    final sentImages =
        provider.lastRequest!.messages.expand((m) => m.images).toList();
    expect(sentImages, isEmpty);
  });
}
