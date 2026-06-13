# AppLens Review Gates — when to invoke which agent

Place the six agent files in `.claude/agents/` and `_REVIEW-PROTOCOL.md` in `docs/`
(referenced by every reviewer). The builder leads; reviewers are gated, not standing.

## The invocation matrix

| Moment                              | flutter-builder | qa-gate | system-design | mobile-platform | ai-sidecar |
|-------------------------------------|:---:|:---:|:---:|:---:|:---:|
| Any coding/fixing task              | ✓   |     |     |     |    |
| End of EVERY session (gate)         |     | ✓   |     |     |    |
| Session defines/changes a contract  |     |     | ✓   |     |    |
| Device-dependent session (5,6,7,11) |     |     |     | ✓   |    |
| Sessions 8.5 and 9 only             |     |     |     |     | ✓  |

`mobile-platform-reviewer` owns the native-mobile / on-device realism lane the
others do not cover (integration_test-vs-WidgetTester divergence, `adb`/`simctl`
permission pre-granting, platform channels, golden stability across devices). It
fires only at the device-dependent sessions (5, 6, 7, 11) and answers "out of my
scope" everywhere else.

Do NOT run all of them every session. Over-invoking reviewers produces noise and re-introduces the
hallucination risk you are trying to remove. The qa-gate reviewer is the workhorse; the others
fire rarely.

## Right now (Sessions 1-4 not yet green)

Your immediate goal is honest green gates, not deep critique. Use this loop per session:

```
Use flutter-builder to finish Session N's tasks and get `dart run melos run ci` green.
When the builder reports green, invoke qa-gate-reviewer to verify the gate is HONESTLY proven
(it will actually run CI and read the tests). Address any BLOCKERS with flutter-builder, then
re-run. Declare Session N done only when CI is green AND qa-gate-reviewer says "gate adequately
proven". If Session N defined a contract, also run system-design-reviewer before declaring done.
```

## Strictness policy (decided)

Evidence-graded blocking:
- BLOCKER (cited, incontestable) → must be fixed before the session is declared done.
- FLAG (cited, debatable) → builder fixes OR justifies in one line; your call.
- SUGGESTION (opinion) → optional.

This means a reviewer can only HALT you on something it proved with a file:line. Imaginary
concerns cannot block, by construction — that is the anti-hallucination guarantee.

## If an agent still hallucinates

It is violating the protocol. The fix is mechanical, not vibes:
- Reply: "Which file:line did you Read for that concern? Show the grep you ran." A hallucinated
  concern cannot answer; it evaporates. A real one gets sharper.
- If an agent repeatedly raises uncited concerns, add to its file: "Your last review raised an
  uncited concern, which is a protocol violation. Re-review reading every file first."
- Track it: if system-design or ai-sidecar reviewers keep returning "clean," they are doing their
  job — do not mistake quietness for uselessness, and do not goad them into finding something.

## Retirement rule

After ~3 sessions, if a reviewer has produced only "clean"/"out of scope", stop invoking it until
its trigger moment genuinely arrives. Apparatus you run out of habit is cost without value — the
same walking-skeleton discipline that governs the product governs the process.
