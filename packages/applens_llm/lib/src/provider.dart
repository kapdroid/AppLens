import 'dart:typed_data';

/// The seam where any LLM — or a human at a desktop chat (the ManualProvider) —
/// is swapped. Sidecar logic speaks only [LlmRequest] / [LlmResult]; it never
/// names a vendor. Adapters (Session 8.5) normalize their provider's native
/// JSON/tool mode to these types.
abstract interface class LlmProvider {
  /// Completes [request], returning schema-validated structured output.
  Future<LlmResult> complete(LlmRequest request);

  /// What this provider can do — used to degrade gracefully (a no-vision
  /// provider falls back to text-only tree diffs rather than assuming vision).
  LlmCapabilities get capabilities;
}

/// The role of a message in a conversation.
enum LlmRole { system, user, assistant }

/// A single message in an [LlmRequest].
class LlmMessage {
  const LlmMessage(this.role, this.text, {this.images = const <LlmImage>[]});

  final LlmRole role;
  final String text;
  final List<LlmImage> images;
}

/// An image attached to a message (e.g. a red diff overlay), as raw bytes.
class LlmImage {
  const LlmImage({required this.bytes, this.mimeType = 'image/png'});

  final Uint8List bytes;
  final String mimeType;
}

/// A provider-neutral completion request. [jsonSchema] declares the shape the
/// result must validate against — output is always structured, never free text.
class LlmRequest {
  const LlmRequest({
    required this.messages,
    required this.jsonSchema,
    this.maxOutputTokens = 2048,
  });

  final List<LlmMessage> messages;
  final Map<String, Object?> jsonSchema;
  final int maxOutputTokens;
}

/// A provider-neutral completion result: the validated JSON object plus token
/// accounting.
class LlmResult {
  const LlmResult({
    required this.json,
    this.inputTokens = 0,
    this.outputTokens = 0,
  });

  final Map<String, Object?> json;
  final int inputTokens;
  final int outputTokens;
}

/// What an [LlmProvider] supports — vision, native JSON mode, and context size.
class LlmCapabilities {
  const LlmCapabilities({
    required this.vision,
    required this.jsonMode,
    required this.maxContextTokens,
  });

  final bool vision;
  final bool jsonMode;
  final int maxContextTokens;
}
