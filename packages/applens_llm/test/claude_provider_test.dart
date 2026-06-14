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

  test('a 200 with a non-JSON body throws LlmException (stays advisory)', () {
    final provider = ClaudeProvider(
      apiKey: 'sk-test',
      httpClient: MockClient(
        (_) async => http.Response('<html>captive portal</html>', 200),
      ),
    );
    expect(provider.complete(_request()), throwsA(isA<LlmException>()));
  });

  test('non-numeric token usage degrades to 0 instead of crashing', () async {
    final provider = ClaudeProvider(
      apiKey: 'sk-test',
      httpClient: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'content': [
              {
                'type': 'text',
                'text': jsonEncode(
                    {'verdict': 'bug', 'reasoning': 'no commit explains it'}),
              },
            ],
            'usage': {'input_tokens': null, 'output_tokens': 'oops'},
          }),
          200,
        ),
      ),
    );

    final result = await provider.complete(_request());

    expect(result.json['verdict'], 'bug');
    expect(result.inputTokens, 0);
    expect(result.outputTokens, 0);
  });

  test('a JSON-object scratchpad block is skipped for the valid block',
      () async {
    final provider = ClaudeProvider(
      apiKey: 'sk-test',
      httpClient: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'content': [
              // A JSON object that parses but doesn't match the schema — it must
              // be skipped, not throw, so the real verdict block is returned.
              {'type': 'text', 'text': '{"thinking":"let me reason"}'},
              {
                'type': 'text',
                'text': jsonEncode(
                    {'verdict': 'bug', 'reasoning': 'no commit explains it'}),
              },
            ],
            'usage': {'input_tokens': 100, 'output_tokens': 20},
          }),
          200,
        ),
      ),
    );

    final result = await provider.complete(_request());

    expect(result.json['verdict'], 'bug');
  });

  test('a prose preamble block is skipped for the JSON block', () async {
    final provider = ClaudeProvider(
      apiKey: 'sk-test',
      httpClient: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'content': [
              {'type': 'text', 'text': 'Here is my analysis:'},
              {
                'type': 'text',
                'text': jsonEncode(
                    {'verdict': 'intended', 'reasoning': 'restyle PR'}),
              },
            ],
            'usage': {'input_tokens': 100, 'output_tokens': 20},
          }),
          200,
        ),
      ),
    );

    final result = await provider.complete(_request());

    expect(result.json['verdict'], 'intended');
  });
}
