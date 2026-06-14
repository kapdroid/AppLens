import 'provider.dart';

/// Adapts a request to what a provider can actually consume. AppLens always
/// packs the full evidence — a diff image *and* a text tree-diff — into the
/// request; this strips what a non-vision provider can't use, so a text-only
/// model still gets the tree diff rather than a dropped or rejected image.
///
/// A vision-capable provider gets the request untouched. Without vision, image
/// attachments are removed; a message that carried only an image (no text
/// fallback) is dropped rather than sent empty. The caller's contract is to
/// pair every diff image with a text tree-diff so evidence survives.
LlmRequest degradeForCapabilities(
  LlmRequest request,
  LlmCapabilities capabilities,
) {
  if (capabilities.vision) return request;
  final messages = <LlmMessage>[];
  for (final message in request.messages) {
    if (message.images.isEmpty) {
      messages.add(message);
    } else if (message.text.isNotEmpty) {
      messages.add(LlmMessage(message.role, message.text));
    }
  }
  return LlmRequest(
    messages: messages,
    jsonSchema: request.jsonSchema,
    maxOutputTokens: request.maxOutputTokens,
  );
}
