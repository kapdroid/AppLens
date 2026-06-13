/// AppLens SDK: the optional in-app package — TestClock, the introspection
/// service extension, and seed hooks — all compiled out of release builds. This
/// is a stub until a later session; it ships only this documented placeholder
/// so the workspace resolves and CI is green from the first commit.
library;

/// Registers the in-app AppLens hooks (clock, introspection, seeds).
Never registerApplensSdk() => throw UnimplementedError(
      'applens_sdk is wired up in a later session (SDK integration tiers, §10).',
    );
