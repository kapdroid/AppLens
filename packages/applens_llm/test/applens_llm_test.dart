import 'dart:typed_data';

import 'package:applens_llm/applens_llm.dart';
import 'package:test/test.dart';

/// A trivial provider that echoes the last message, exercising the port shape.
class _EchoProvider implements LlmProvider {
  @override
  LlmCapabilities get capabilities => const LlmCapabilities(
        vision: false,
        jsonMode: true,
        maxContextTokens: 8192,
      );

  @override
  Future<LlmResult> complete(LlmRequest request) async =>
      LlmResult(json: <String, Object?>{'echo': request.messages.last.text});
}

void main() {
  test('a provider returns schema-shaped JSON through the port', () async {
    final provider = _EchoProvider();
    final result = await provider.complete(
      const LlmRequest(
        messages: [LlmMessage(LlmRole.user, 'classify this failure')],
        jsonSchema: <String, Object?>{'type': 'object'},
      ),
    );
    expect(result.json['echo'], 'classify this failure');
    expect(provider.capabilities.vision, isFalse);
    expect(provider.capabilities.jsonMode, isTrue);
  });

  test('LlmImage defaults to PNG', () {
    final image = LlmImage(bytes: Uint8List(0));
    expect(image.mimeType, 'image/png');
  });
}
