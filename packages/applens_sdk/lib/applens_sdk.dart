/// AppLens SDK: the optional in-app package for Tier-1 integration (§10) — the
/// state registry the app uses to expose identity flags and guard preconditions
/// to the runner, debug-only so it compiles out of release builds. Tier-0 (zero
/// integration) needs none of this; the runner infers flags from the UI instead
/// (`UiInferenceFlagSource`). TestClock and seed hooks layer on here later.
library;

export 'src/applens_state.dart';
