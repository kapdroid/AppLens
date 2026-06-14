import 'dart:convert';
import 'dart:typed_data';

import 'package:applens_llm/applens_llm.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

const _schema = <String, Object?>{
  'type': 'object',
  'required': ['verdict', 'reasoning'],
  'properties': {
    'verdict': {
      'type': 'string',
      'enum': ['bug', 'intended', 'flake'],
    },
    'reasoning': {'type': 'string'},
  },
};

LlmRequest _request() => LlmRequest(
      messages: [
        const LlmMessage(LlmRole.system, 'You are AppLens triage.'),
        LlmMessage(
          LlmRole.user,
          'Is this drift a bug?',
          images: [
            LlmImage(bytes: Uint8List.fromList([1, 2, 3]))
          ],
        ),
      ],
      jsonSchema: _schema,
      maxOutputTokens: 512,
    );

/// A canned Anthropic Messages API success body whose text block is [json].
http.Response _ok(Map<String, Object?> json) => http.Response(
      jsonEncode({
        'content': [
          {'type': 'text', 'text': jsonEncode(json)},
        ],
        'usage': {'input_tokens': 100, 'output_tokens': 20},
      }),
      200,
    );

void main() {
  test('parses a schema-valid verdict and token usage', () async {
    final provider = ClaudeProvider(
      apiKey: 'sk-test',
      httpClient: MockClient(
        (_) async => _ok({'verdict': 'intended', 'reasoning': 'restyle PR'}),
      ),
    );

    final result = await provider.complete(_request());

    expect(result.json['verdict'], 'intended');
    expect(result.inputTokens, 100);
    expect(result.outputTokens, 20);
  });

  test('builds a well-formed Messages API request', () async {
    late Map<String, Object?> sent;
    late Map<String, String> headers;
    final provider = ClaudeProvider(
      apiKey: 'sk-test',
      httpClient: MockClient((req) async {
        sent = jsonDecode(req.body) as Map<String, Object?>;
        headers = req.headers;
        return _ok({'verdict': 'flake', 'reasoning': 'nondeterministic'});
      }),
    );

    await provider.complete(_request());

    expect(sent['model'], 'claude-opus-4-8');
    expect(sent['max_tokens'], 512);
    expect(sent['system'], contains('AppLens triage')); // system role hoisted
    final format = (sent['output_config'] as Map)['format'] as Map;
    expect(format['type'], 'json_schema');
    expect(format['schema'], _schema);
    final messages = sent['messages'] as List;
    final content = (messages.single as Map)['content'] as List;
    expect(content.any((b) => (b as Map)['type'] == 'image'), isTrue);
    expect(headers['x-api-key'], 'sk-test');
    expect(headers['anthropic-version'], '2023-06-01');
  });

  test('a non-200 response throws LlmException', () {
    final provider = ClaudeProvider(
      apiKey: 'sk-test',
      httpClient: MockClient((_) async => http.Response('rate limited', 429)),
    );
    expect(provider.complete(_request()), throwsA(isA<LlmException>()));
  });

  test('output that violates the schema throws LlmException', () {
    final provider = ClaudeProvider(
      apiKey: 'sk-test',
      httpClient: MockClient((_) async => _ok({'verdict': 'nope'})),
    );
    expect(provider.complete(_request()), throwsA(isA<LlmException>()));
  });
}
