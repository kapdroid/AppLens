# Triage evals

Evidence→verdict pairs that validate the AI sidecar (ARCHITECTURE.md §12,
CLAUDE.md standing verification). Each case is the evidence triage sees plus the
verdict a human gave — the regression corpus the automated providers are scored
against. The human verdict is ground truth; a provider's job is to reproduce it.

Per CLAUDE.md, hand triage during Phases 1–2 and save each failure here. From
Session 9 on, the same cases also exercise `applens triage` across providers
(the provider-swap and overturn-rate checks).

## Layout

```
NNN-short-slug/
  evidence.md     # what triage is shown (node, tree diff, commits, image refs)
  verdict.json    # the ground-truth human decision, in the triage schema
```

`verdict.json` matches `triageVerdictSchema` (applens_llm): `classification`
(bug | intended | flake), `confidence`, `reasoning`, optional `causal_commit`.

## Scoring

Overturn rate = human-overturned ÷ decided verdicts (§9). Above ~10%, fix the
evidence package — not the model, and never the policy. AI is advisory: a verdict
never gates a run.
