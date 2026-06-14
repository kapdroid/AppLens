import 'package:applens_llm/applens_llm.dart';
import 'package:test/test.dart';

void main() {
  test('returns its scripted result and records the request', () async {
    final provider = FakeLlmProvider(
      const LlmResult(json: {'verdict': 'flake'}, outputTokens: 5),
    );

    final result = await provider.complete(
      const LlmRequest(
        messages: [LlmMessage(LlmRole.user, 'hi')],
        jsonSchema: {'type': 'object'},
      ),
    );

    expect(result.json['verdict'], 'flake');
    expect(provider.lastRequest?.messages.single.text, 'hi');
  });

  test('exposes capabilities so callers can degrade (e.g. no vision)', () {
    final noVision = FakeLlmProvider(
      const LlmResult(json: {}),
      capabilities: const LlmCapabilities(
        vision: false,
        jsonMode: true,
        maxContextTokens: 8000,
      ),
    );
    expect(noVision.capabilities.vision, isFalse);
  });
}
