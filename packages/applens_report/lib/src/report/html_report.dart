import 'package:applens_core/applens_core.dart';

import 'graph_view.dart';

/// Renders a run as a static, dependency-free HTML page (ARCHITECTURE.md §13):
/// summary + node coverage, a per-visit table, and — for each failure — the
/// self-locating path (`<node file>:payload.assertions[i]`) plus a rendered
/// neighbourhood subgraph with the failing node in red (§5). No human ever has
/// to search the other nodes.
String renderRunReport(RunRecord run, Graph graph) {
  final total = graph.nodes.length;
  final visited = {for (final visit in run.visits) visit.expectedNodeId};
  final counts = <NodeOutcome, int>{};
  for (final visit in run.visits) {
    counts[visit.outcome] = (counts[visit.outcome] ?? 0) + 1;
  }
  final coverage = total == 0 ? 0 : (visited.length * 100 / total).round();

  final out = StringBuffer()
    ..writeln('<!doctype html>')
    ..writeln('<html lang="en"><head><meta charset="utf-8">')
    ..writeln('<title>AppLens — run ${escapeXml(run.id)}</title>')
    ..writeln('<style>$_css</style></head><body>')
    ..writeln('<h1>AppLens run report</h1>')
    ..writeln(
      '<p class="meta">run <code>${escapeXml(run.id)}</code> · strategy '
      '<code>${escapeXml(run.strategy)}</code> · '
      '<code>${escapeXml(run.graphHash)}</code> · seed ${run.seed}</p>',
    )
    ..writeln('<h2>Summary</h2><ul>')
    ..writeln('<li>node coverage: ${visited.length}/$total ($coverage%)</li>');
  for (final outcome in NodeOutcome.values) {
    final count = counts[outcome] ?? 0;
    if (count > 0) {
      out.writeln('<li class="${outcome.name}">${outcome.name}: $count</li>');
    }
  }
  out
    ..writeln('</ul>')
    ..writeln('<h2>Visits</h2><table><thead><tr>')
    ..writeln('<th>step</th><th>node</th><th>outcome</th><th>matched</th>')
    ..writeln('</tr></thead><tbody>');
  for (final visit in run.visits) {
    final unexpected = visit.isUnexpectedTransition ? ' (unexpected)' : '';
    out.writeln(
      '<tr class="${visit.outcome.name}"><td>${visit.step}</td>'
      '<td><code>${escapeXml(visit.expectedNodeId)}</code></td>'
      '<td>${visit.outcome.name}$unexpected</td>'
      '<td>${escapeXml(visit.matchedNodeId ?? '—')}</td></tr>',
    );
  }
  out.writeln('</tbody></table>');

  final failures = run.visits
      .where(
        (v) =>
            v.outcome == NodeOutcome.failedSoft ||
            v.outcome == NodeOutcome.failedHard,
      )
      .toList();
  if (failures.isNotEmpty) {
    out.writeln('<h2>Failures</h2>');
    for (final visit in failures) {
      final node = graph.byId[visit.expectedNodeId];
      final path = node?.source?.source ?? visit.expectedNodeId;
      out
        ..writeln('<section class="failure">')
        ..writeln(
          '<h3><code>${escapeXml(visit.expectedNodeId)}</code> — '
          '${visit.outcome.name}</h3>',
        );
      if (visit.outcome == NodeOutcome.failedSoft) {
        out.writeln('<ul>');
        for (var i = 0; i < visit.assertions.length; i++) {
          final result = visit.assertions[i];
          if (!result.skipped && !result.passed) {
            out.writeln(
              '<li><code>${escapeXml(path)}:payload.assertions[$i]</code> — '
              '${escapeXml(result.type)}: ${escapeXml(result.detail)}</li>',
            );
          }
        }
        out.writeln('</ul>');
      } else {
        final landed = visit.matchedNodeId == null
            ? 'unreachable'
            : 'an unexpected transition to ${escapeXml(visit.matchedNodeId!)}';
        out.writeln(
          '<p><code>${escapeXml(path)}</code> — expected node $landed</p>',
        );
      }
      out
        ..writeln(
          renderNeighborhood(
            graph,
            visit.expectedNodeId,
            failedIds: {visit.expectedNodeId},
          ),
        )
        ..writeln('</section>');
    }
  }

  out.writeln('</body></html>');
  return out.toString();
}

const String _css = '''
body{font-family:system-ui,sans-serif;margin:2rem;color:#222}
code{font-family:monospace}
.meta{color:#666}
table{border-collapse:collapse;width:100%}
th,td{border:1px solid #ddd;padding:.4rem .6rem;text-align:left}
tr.passed{background:#eaf7ea}
tr.failedSoft,tr.failedHard{background:#fdecea}
tr.blocked{background:#fff4e5}
tr.pending{background:#fffbe6}
li.failedSoft,li.failedHard,li.blocked{color:#b00020}
section.failure{border:1px solid #f0c0c0;border-radius:8px;padding:1rem;margin:1rem 0}
''';
