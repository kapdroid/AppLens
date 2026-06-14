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

    // A 200 with a non-JSON body (proxy/WAF HTML, captive portal) must surface
    // as an LlmException — the port's contract is that only LlmException escapes,
    // so a provider failure stays advisory and never aborts the run.
    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException catch (e) {
      throw LlmException('Claude response was not JSON: ${e.message}');
    }
    if (decoded is! Map) {
      throw const LlmException('Claude response was not a JSON object');
    }
    final json = _extractJson(decoded, request.jsonSchema);
    final usage = decoded['usage'];
    return LlmResult(
      json: json,
      inputTokens: usage is Map ? _asInt(usage['input_tokens']) : 0,
      outputTokens: usage is Map ? _asInt(usage['output_tokens']) : 0,
    );
  }

  /// Token counts default to 0 if the field is absent or not a number, so a
  /// malformed `usage` block can't crash an otherwise-valid response.
  int _asInt(Object? value) => value is num ? value.toInt() : 0;

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
    // Try each text block, not just the first — models often emit a short prose
    // block before the structured JSON one, even under output_config.format.
    final texts = [
      for (final block in content.whereType<Map<String, dynamic>>())
        if (block['type'] == 'text' && block['text'] is String)
          block['text'] as String,
    ];
    if (texts.isEmpty) {
      throw const LlmException('Claude response had no text');
    }
    String? lastSchemaError;
    for (final text in texts) {
      final Object? parsed;
      try {
        parsed = jsonDecode(text);
      } on FormatException {
        continue; // a prose preamble block; try the next
      }
      if (parsed is! Map) {
        continue; // a JSON array/scalar block; try the next
      }
      final json = parsed.cast<String, Object?>();
      final errors = validateAgainstSchema(json, schema);
      if (errors.isNotEmpty) {
        // A JSON object that isn't the verdict (e.g. a scratchpad block before
        // the real one). Remember the error, try the next block.
        lastSchemaError = errors.join('; ');
        continue;
      }
      return json;
    }
    throw LlmException(lastSchemaError == null
        ? 'Claude output had no valid JSON text block'
        : 'Claude output failed schema: $lastSchemaError');
  }
}
