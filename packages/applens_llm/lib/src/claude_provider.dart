import 'dart:convert';

import 'package:http/http.dart' as http;

import 'provider.dart';
import 'schema.dart';

/// An [LlmProvider] backed by Anthropic's Messages API (BYO-key). Dart has no
/// official Anthropic SDK, so this is a thin raw-HTTP adapter over
/// `POST /v1/messages` using `package:http`. It requests schema-constrained JSON
/// via `output_config.format`, then re-validates the result against the same
/// schema (the port's contract). The default model is `claude-opus-4-8`.
///
/// The API key is supplied by the caller (env var / config) — never hard-coded.
/// Inject [httpClient] (e.g. a mock) to test without a live key.
class ClaudeProvider implements LlmProvider {
  ClaudeProvider({
    required String apiKey,
    this.model = 'claude-opus-4-8',
    http.Client? httpClient,
    Uri? endpoint,
    this.anthropicVersion = '2023-06-01',
  })  : _apiKey = apiKey,
        _http = httpClient ?? http.Client(),
        _endpoint =
            endpoint ?? Uri.parse('https://api.anthropic.com/v1/messages');

  final String _apiKey;
  final String model;
  final http.Client _http;
  final Uri _endpoint;
  final String anthropicVersion;

  @override
  LlmCapabilities get capabilities => const LlmCapabilities(
        vision: true,
        jsonMode: true,
        maxContextTokens: 1000000,
      );

  @override
  Future<LlmResult> complete(LlmRequest request) async {
    final http.Response response;
    try {
      response = await _http.post(
        _endpoint,
        headers: {
          'content-type': 'application/json',
          'x-api-key': _apiKey,
          'anthropic-version': anthropicVersion,
        },
        body: jsonEncode(_buildBody(request)),
      );
    } on Object catch (e) {
      throw LlmException('Claude request failed: $e');
    }

    if (response.statusCode != 200) {
      throw LlmException('Claude API ${response.statusCode}: ${response.body}');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw const LlmException('Claude response was not a JSON object');
    }
    final json = _extractJson(decoded, request.jsonSchema);
    final usage = decoded['usage'];
    return LlmResult(
      json: json,
      inputTokens:
          usage is Map ? (usage['input_tokens'] as num?)?.toInt() ?? 0 : 0,
      outputTokens:
          usage is Map ? (usage['output_tokens'] as num?)?.toInt() ?? 0 : 0,
    );
  }

  Map<String, Object?> _buildBody(LlmRequest request) {
    final systemParts = <String>[];
    final messages = <Map<String, Object?>>[];
    for (final message in request.messages) {
      if (message.role == LlmRole.system) {
        systemParts.add(message.text);
        continue;
      }
      messages.add({
        'role': message.role == LlmRole.assistant ? 'assistant' : 'user',
        'content': [
          if (message.text.isNotEmpty) {'type': 'text', 'text': message.text},
          for (final image in message.images)
            {
              'type': 'image',
              'source': {
                'type': 'base64',
                'media_type': image.mimeType,
                'data': base64Encode(image.bytes),
              },
            },
        ],
      });
    }
    return {
      'model': model,
      'max_tokens': request.maxOutputTokens,
      if (systemParts.isNotEmpty) 'system': systemParts.join('\n\n'),
      'messages': messages,
      // Structured outputs: constrain the response to the declared schema.
      'output_config': {
        'format': {'type': 'json_schema', 'schema': request.jsonSchema},
      },
    };
  }

  Map<String, Object?> _extractJson(
    Map<dynamic, dynamic> decoded,
    Map<String, Object?> schema,
  ) {
    final content = decoded['content'];
    if (content is! List) {
      throw const LlmException('Claude response had no content blocks');
    }
    final textBlock = content.whereType<Map<String, dynamic>>().firstWhere(
          (block) => block['type'] == 'text',
          orElse: () => throw const LlmException('Claude response had no text'),
        );
    final Object? parsed;
    try {
      parsed = jsonDecode(textBlock['text'] as String);
    } on Object {
      throw const LlmException('Claude output was not valid JSON');
    }
    if (parsed is! Map) {
      throw const LlmException('Claude output was not a JSON object');
    }
    final json = parsed.cast<String, Object?>();
    final errors = validateAgainstSchema(json, schema);
    if (errors.isNotEmpty) {
      throw LlmException('Claude output failed schema: ${errors.join('; ')}');
    }
    return json;
  }
}
