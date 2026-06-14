/// AppLens LLM: the provider-agnostic LlmProvider port and its adapters.
/// Sidecar logic depends only on this port, never on a specific vendor.
library;

export 'src/author.dart';
export 'src/claude_provider.dart';
export 'src/commit_source.dart';
export 'src/degrade.dart';
export 'src/evidence.dart';
export 'src/fake_provider.dart';
export 'src/manual_provider.dart';
export 'src/provider.dart';
export 'src/schema.dart';
export 'src/triage_engine.dart';
