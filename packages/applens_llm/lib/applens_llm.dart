/// AppLens LLM: the provider-agnostic LlmProvider port and its adapters.
/// Sidecar logic depends only on this port, never on a specific vendor.
library;

export 'src/fake_provider.dart';
export 'src/manual_provider.dart';
export 'src/provider.dart';
export 'src/schema.dart';
