import 'provider.dart';

/// A scripted [LlmProvider] for tests and for exercising the capability-
/// degradation path (give it `vision: false` to prove triage falls back to
/// text-only). Records the last request so callers can assert what was sent.
class FakeLlmProvider implements LlmProvider {
  FakeLlmProvider(
    this._result, {
    LlmCapabilities? capabilities,
  }) : capabilities = capabilities ??
            const LlmCapabilities(
              vision: true,
              jsonMode: true,
              maxContextTokens: 200000,
            );

  final LlmResult _result;
  LlmRequest? lastRequest;

  @override
  final LlmCapabilities capabilities;

  @override
  Future<LlmResult> complete(LlmRequest request) async {
    lastRequest = request;
    return _result;
  }
}
