/// AppLens crawler: budgeted breadth-first exploration that proposes a draft
/// graph, and rerun-mode drift detection against the approved graph (Phase 4,
/// ARCHITECTURE.md §11). The draft is always a PR — never auto-merged.
library;

export 'src/crawl_session.dart';
export 'src/crawler.dart';
