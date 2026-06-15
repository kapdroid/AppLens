import 'dart:convert';

import 'package:applens_core/applens_core.dart';

import 'flow_analysis.dart';
import 'graph_view.dart';

/// Renders a run as a static, dependency-free, self-contained HTML page
/// (ARCHITECTURE.md §13) — a QA-grade report: a verdict banner, the flows it
/// walked (the broken one marked at its failing step), per-issue steps-to-
/// reproduce + a flow stepper, and a per-screen tabbed visual/semantic
/// comparison. Light and dark themes (auto via `prefers-color-scheme`, with a
/// manual toggle). Triage (from `applens triage`) is folded in but advisory —
/// it never changes the pass/fail summary or the exit code (§9).
String renderRunReport(RunRecord run, Graph graph, {TriageReport? triage}) {
  final total = graph.nodes.length;
  final visited = {
    for (final visit in run.visits)
      if (graph.byId.containsKey(visit.expectedNodeId)) visit.expectedNodeId,
  };
  final counts = <NodeOutcome, int>{};
  for (final visit in run.visits) {
    counts[visit.outcome] = (counts[visit.outcome] ?? 0) + 1;
  }
  final coverage = total == 0 ? 0 : (visited.length * 100 / total).round();
  final verdicts = {
    for (final v in triage?.verdicts ?? const <TriageVerdict>[]) v.nodeId: v,
  };
  final analysis = FlowAnalysis.of(run, graph);
  final flowsByIndex = {for (final f in analysis.flows) f.index: f};

  final red = run.visits.any((v) =>
      v.outcome == NodeOutcome.failedSoft ||
      v.outcome == NodeOutcome.failedHard ||
      v.outcome == NodeOutcome.blocked);
  final anyPending = run.visits.any((v) => v.outcome == NodeOutcome.pending);
  final verdict = red ? 'red' : (anyPending ? 'pending' : 'green');

  final out = StringBuffer()
    ..writeln('<!doctype html>')
    ..writeln('<html lang="en"><head><meta charset="utf-8">')
    ..writeln('<meta name="viewport" content="width=device-width,'
        'initial-scale=1">')
    ..writeln('<title>AppLens — run ${escapeXml(run.id)}</title>')
    ..writeln('<style>$_css</style>')
    ..writeln('<script>$_themeScript</script></head><body><div class="wrap">')
    ..writeln('<button class="toggle" onclick="alToggleTheme()" '
        'aria-label="toggle light/dark theme">◐ theme</button>')
    ..writeln('<h1>AppLens run report</h1>')
    ..writeln(
      '<p class="meta">strategy <code>${escapeXml(run.strategy)}</code> · '
      '${run.visits.length} steps · '
      'node coverage: ${visited.length}/$total ($coverage%) · '
      '<code>${escapeXml(run.graphHash)}</code></p>',
    );

  // Verdict banner + metric cards.
  final bannerText = verdict == 'green'
      ? '✓ GREEN — all assertions passed'
      : verdict == 'pending'
          ? '⚠ PENDING — baselines awaiting approval'
          : '✗ RED — ${analysis.flows.where((f) => f.failed).length} flow(s) '
              'with issues';
  out
    ..writeln('<div class="banner $verdict">$bannerText</div>')
    ..writeln('<div class="metrics">');
  _metric(out, 'flows', '${analysis.flows.length}');
  _metric(out, 'passed', '${counts[NodeOutcome.passed] ?? 0}', cls: 'tier-ok');
  final failedCount = (counts[NodeOutcome.failedSoft] ?? 0) +
      (counts[NodeOutcome.failedHard] ?? 0);
  _metric(out, 'failed', '$failedCount',
      cls: failedCount > 0 ? 'tier-bad' : '');
  _metric(out, 'coverage', '$coverage%');
  out.writeln('</div>');
  if (triage != null) {
    final rate = (triage.overturnRate * 100).round();
    out.writeln('<p class="note">triage: ${triage.verdicts.length} '
        'verdict(s), ${triage.proposals.length} proposal(s) · '
        'human-overturn rate $rate%</p>');
  }

  // Flows — which flow has the issue, marked at its failing step.
  out.writeln('<h2>Flows</h2>');
  for (final flow in analysis.flows) {
    final failAt = flow.firstFailure?.expectedNodeId;
    out.write('<div class="flow${flow.failed ? ' bad' : ''}">');
    out.write(
        flow.failed ? '<span>✗</span>' : '<span class="tier-ok">✓</span>');
    for (var i = 0; i < flow.nodes.length; i++) {
      if (i > 0) out.write('<span class="sep">→</span>');
      final node = flow.nodes[i];
      final bad = node == failAt;
      out.write('<span class="chip${bad ? ' bad' : ''}">'
          '${escapeXml(node)}</span>');
    }
    out.write('<span class="status">'
        '${flow.failed ? 'failed at ${escapeXml(failAt ?? '?')}' : 'passed'}'
        '</span></div>');
  }

  // Issues — STR + flow stepper + evidence per failing visit.
  final failures = run.visits
      .where((v) =>
          v.outcome == NodeOutcome.failedSoft ||
          v.outcome == NodeOutcome.failedHard)
      .toList();
  if (triage != null) {
    failures.sort((a, b) => _verdictRank(verdicts[a.expectedNodeId])
        .compareTo(_verdictRank(verdicts[b.expectedNodeId])));
  }
  if (failures.isNotEmpty) {
    out.writeln('<h2>Issues</h2>');
    for (final visit in failures) {
      _renderIssue(out, run, graph, visit, flowsByIndex[visit.flow],
          verdicts[visit.expectedNodeId]);
    }
  }

  // Screens — per-screen tabbed visual + semantic comparison (pass and fail).
  _renderScreens(out, run, graph);

  // Pending — intended changes awaiting confirmation.
  final pendings =
      run.visits.where((v) => v.outcome == NodeOutcome.pending).toList();
  if (pendings.isNotEmpty) {
    out.writeln('<h2>Pending — intended changes awaiting confirmation</h2>');
    for (final visit in pendings) {
      final path = graph.byId[visit.expectedNodeId]?.source?.source ??
          visit.expectedNodeId;
      out
        ..writeln('<section class="pending">')
        ..writeln('<h3><code>${escapeXml(visit.expectedNodeId)}</code> — '
            'pending</h3><ul>');
      for (final result
          in visit.assertions.where((a) => a.type == 'visual_pending')) {
        out.writeln('<li><code>${escapeXml(path)}</code> — '
            '${_confirmLine(result.detail)}</li>');
      }
      out
        ..writeln('</ul>')
        ..writeln('</section>');
    }
  }

  if (triage != null) {
    _renderClusters(out, triage);
  }

  // Full visit table, last — the complete record for reference.
  out
    ..writeln('<h2>Visits</h2><table><thead><tr>')
    ..writeln('<th>step</th><th>flow</th><th>node</th><th>outcome</th>'
        '<th>matched</th></tr></thead><tbody>');
  for (final visit in run.visits) {
    final unexpected = visit.isUnexpectedTransition ? ' (unexpected)' : '';
    out.writeln(
      '<tr class="${visit.outcome.name}"><td>${visit.step}</td>'
      '<td>${visit.flow}</td>'
      '<td><code>${escapeXml(visit.expectedNodeId)}</code></td>'
      '<td>${visit.outcome.name}$unexpected</td>'
      '<td>${escapeXml(visit.matchedNodeId ?? '—')}</td></tr>',
    );
  }
  out
    ..writeln('</tbody></table>')
    ..writeln('</div></body></html>');
  return out.toString();
}

void _metric(StringBuffer out, String label, String value, {String cls = ''}) {
  out.write('<div class="metric"><div class="k">${escapeXml(label)}</div>'
      '<div class="v $cls">${escapeXml(value)}</div></div>');
}

/// One failing visit: heading, STR/flow stepper (the failing step flagged), the
/// localized evidence images, optional triage badge, and the neighbourhood SVG.
void _renderIssue(StringBuffer out, RunRecord run, Graph graph, NodeVisit visit,
    FlowView? flow, TriageVerdict? verdict) {
  final path =
      graph.byId[visit.expectedNodeId]?.source?.source ?? visit.expectedNodeId;
  out
    ..writeln('<section class="card">')
    ..writeln('<h3><code>${escapeXml(visit.expectedNodeId)}</code> — '
        '${visit.outcome.name} '
        '<span class="note">${escapeXml(path)}</span></h3>');

  // The reason, attached to the failing (last) STR step below.
  final reason = visit.outcome == NodeOutcome.failedSoft
      ? visit.assertions
          .where((a) => !a.skipped && !a.passed)
          .map((a) => '${a.type}: ${a.detail}')
          .join('; ')
      : (visit.matchedNodeId == null
          ? 'expected node unreachable'
          : 'unexpected transition to ${visit.matchedNodeId}');

  if (flow != null) {
    final steps = stepsToReproduce(flow, visit.expectedNodeId);
    out.writeln('<p class="note">Steps to reproduce</p><ol class="str">');
    for (var i = 0; i < steps.length; i++) {
      final step = steps[i];
      final isLast = i == steps.length - 1;
      out.write('<li${isLast ? ' class="fail"' : ''}>'
          '<span class="num">${i + 1}</span>'
          '<span class="chip">${escapeXml(step.node)}</span>');
      if (step.action != null) {
        out.write(' <span class="act">${escapeXml(step.action!)}</span>');
      } else {
        out.write(' <span class="act">launch app</span>');
      }
      if (isLast) {
        out.write(' <span class="act">→ ${escapeXml(reason)}</span>');
      }
      out.write('</li>');
    }
    out.writeln('</ol>');
  } else {
    out.writeln('<p>${escapeXml(reason)}</p>');
  }

  for (final art in visit.artifacts) {
    final bytes = art.bytes;
    if ((art.kind == 'annotated' || art.kind == 'diff') && bytes != null) {
      out.writeln(_figure(art.kind, art.description, bytes));
    }
  }
  if (verdict != null) {
    out.writeln(_verdictBadge(verdict));
  }
  out
    ..writeln(renderNeighborhood(graph, visit.expectedNodeId,
        failedIds: {visit.expectedNodeId}))
    ..writeln('</section>');
}

/// Per-screen tabbed comparison: every visited node gets a tab showing its tier
/// results and the visual/semantic images (the approved baseline on a pass, the
/// diff/annotated overlay on a fail). Screens without a baseline say so.
void _renderScreens(StringBuffer out, RunRecord run, Graph graph) {
  final firstVisit = <String, NodeVisit>{};
  for (final visit in run.visits) {
    firstVisit.putIfAbsent(visit.expectedNodeId, () => visit);
  }
  if (firstVisit.isEmpty) return;
  final nodes = firstVisit.keys.toList()..sort();
  out.writeln('<h2>Screens</h2><div class="tabs">');
  for (var i = 0; i < nodes.length; i++) {
    final visit = firstVisit[nodes[i]]!;
    final mark = visit.outcome == NodeOutcome.passed
        ? '✓'
        : (visit.outcome == NodeOutcome.pending ? '⚠' : '✗');
    out
      ..write('<input type="radio" name="screen" id="scr-$i"'
          '${i == 0 ? ' checked' : ''}>')
      ..write('<label for="scr-$i">$mark ${escapeXml(nodes[i])}</label>')
      ..write('<div class="panel">');
    _renderScreenPanel(out, visit);
    out.write('</div>');
  }
  out.writeln('</div>');
}

void _renderScreenPanel(StringBuffer out, NodeVisit visit) {
  final images = visit.artifacts.where((a) =>
      a.bytes != null &&
      (a.kind == 'visual_baseline' ||
          a.kind == 'capture' ||
          a.kind == 'diff' ||
          a.kind == 'annotated'));
  if (images.isEmpty) {
    out.write('<p class="note">No approved baseline for this screen — record '
        'one with <code>applens approve</code>.</p>');
  } else {
    out.write('<div class="shots">');
    for (final art in images) {
      out.write(_figure(_imageLabel(art.kind), art.description, art.bytes!));
    }
    out.write('</div>');
  }
  out.write('<table><tbody>');
  if (visit.assertions.isEmpty) {
    out.write('<tr><td class="note">no assertions on this screen</td></tr>');
  }
  for (final a in visit.assertions) {
    final cls = a.skipped ? 'tier-skip' : (a.passed ? 'tier-ok' : 'tier-bad');
    final state = a.skipped ? 'skipped' : (a.passed ? 'passed' : 'failed');
    out.write('<tr><td>${_tierLabel(a.tierOrder)} · '
        '${escapeXml(a.type)}</td>'
        '<td class="$cls">$state${a.detail.isEmpty ? '' : ' · '
            '${escapeXml(a.detail)}'}</td></tr>');
  }
  out.write('</tbody></table>');
}

String _figure(String label, String description, List<int> bytes) =>
    '<figure class="evidence"><img alt="${escapeXml(label)}" '
    'src="data:image/png;base64,${base64Encode(bytes)}"/>'
    '<figcaption>${escapeXml(label)} — ${escapeXml(description)}'
    '</figcaption></figure>';

String _imageLabel(String kind) => switch (kind) {
      'visual_baseline' => 'baseline',
      'capture' => 'observed',
      'diff' => 'diff',
      'annotated' => 'highlight',
      _ => kind,
    };

String _tierLabel(int order) => switch (order) {
      5 => 'guard',
      10 => 'tier 1 widgets',
      20 => 'tier 2 layout',
      25 => 'tier 2.5 semantic',
      30 => 'tier 3 visual',
      _ => 'tier $order',
    };

int _verdictRank(TriageVerdict? verdict) {
  switch (verdict?.classification) {
    case TriageClass.bug:
      return 0;
    case null:
      return 1;
    case TriageClass.flake:
      return 2;
    case TriageClass.intended:
      return 3;
  }
}

String _verdictBadge(TriageVerdict verdict) {
  final pct = (verdict.confidence * 100).round();
  final commit = verdict.causalCommit == null
      ? ''
      : ' · commit <code>${escapeXml(verdict.causalCommit!)}</code>';
  return '<p class="verdict ${verdict.classification.name}">'
      'triage: <strong>${verdict.classification.name}</strong> ($pct%)$commit'
      '<br>${escapeXml(verdict.reasoning)}</p>';
}

void _renderClusters(StringBuffer out, TriageReport triage) {
  final clustered = <String, List<TriageVerdict>>{};
  for (final v in triage.verdicts) {
    if (v.cluster != null) {
      (clustered[v.cluster!] ??= []).add(v);
    }
  }
  if (clustered.isEmpty) return;
  out.writeln('<h2>Triage clusters</h2>');
  clustered.forEach((cause, members) {
    out
      ..writeln('<section class="cluster">')
      ..writeln('<h3>cause <code>${escapeXml(cause)}</code> — '
          '${members.length} node(s)</h3><ul>');
    for (final v in members) {
      out.writeln('<li><code>${escapeXml(v.nodeId)}</code> — '
          '${v.classification.name}</li>');
    }
    out
      ..writeln('</ul>')
      ..writeln('</section>');
  });
}

String _confirmLine(String detail) {
  final match = RegExp(r'https?://\S+').firstMatch(detail);
  if (match == null) {
    return escapeXml(detail);
  }
  final url = match.group(0)!;
  final text = detail.replaceFirst(url, '').trim();
  return '${escapeXml(text)} <a href="${escapeXml(url)}">Confirm in PR ↗</a>';
}

const String _themeScript = '''
(function(){var k="applens-theme",s=localStorage.getItem(k);
if(s)document.documentElement.setAttribute("data-theme",s);})();
function alToggleTheme(){var r=document.documentElement,
c=r.getAttribute("data-theme")||(matchMedia("(prefers-color-scheme: dark)").matches?"dark":"light"),
n=c==="dark"?"light":"dark";r.setAttribute("data-theme",n);
localStorage.setItem("applens-theme",n);}''';

const String _lightTokens =
    '--bg:#ffffff;--surface:#f5f7f9;--fg:#1b2733;--muted:#5f6b7a;'
    '--border:#e2e6ea;--danger:#b00020;--danger-bg:#fdecea;--success:#1d7a46;'
    '--success-bg:#eaf7ea;--warning:#9a6b00;--warning-bg:#fff4e5;'
    '--info:#185fa5;--info-bg:#e6f1fb;--al-edge:#9aa0a6;--al-node-bg:#e7f1ff;'
    '--al-node-stroke:#5b8def;--al-node-fail-bg:#f8d7da;'
    '--al-node-fail-stroke:#b00020;--al-node-focus:#b00020;--al-label:#1b2733';

const String _darkTokens =
    '--bg:#15191e;--surface:#1d2329;--fg:#d7dde3;--muted:#9aa4af;'
    '--border:#2c343c;--danger:#e57373;--danger-bg:#3a1e1e;--success:#7bc492;'
    '--success-bg:#16301f;--warning:#e0b15a;--warning-bg:#332a14;'
    '--info:#6ea8e0;--info-bg:#14242f;--al-edge:#5f6368;--al-node-bg:#1b2a3a;'
    '--al-node-stroke:#4a7fb5;--al-node-fail-bg:#3a1e1e;'
    '--al-node-fail-stroke:#e57373;--al-node-focus:#e57373;--al-label:#d7dde3';

final String _css = ':root{$_lightTokens}'
    '@media(prefers-color-scheme:dark){:root:not([data-theme="light"])'
    '{$_darkTokens}}'
    ':root[data-theme="dark"]{$_darkTokens}'
    '*{box-sizing:border-box}'
    'body{font-family:system-ui,-apple-system,sans-serif;margin:0;'
    'background:var(--bg);color:var(--fg);line-height:1.5}'
    '.wrap{position:relative;max-width:980px;margin:0 auto;padding:1.5rem}'
    'code{font-family:ui-monospace,monospace;font-size:.9em}'
    'h1{font-size:22px;margin:0}h2{font-size:18px;margin:1.6rem 0 .6rem}'
    'h3{font-size:15px;margin:0 0 .5rem}'
    '.meta{color:var(--muted);font-size:13px;margin:.3rem 0 0}'
    '.toggle{position:absolute;top:1.5rem;right:1.5rem;background:var(--surface);'
    'border:1px solid var(--border);border-radius:8px;padding:6px 10px;'
    'cursor:pointer;color:var(--fg);font-size:13px}'
    '.banner{padding:.8rem 1rem;border-radius:10px;font-weight:600;'
    'margin:1.2rem 0 .6rem}'
    '.banner.red{background:var(--danger-bg);color:var(--danger)}'
    '.banner.green{background:var(--success-bg);color:var(--success)}'
    '.banner.pending{background:var(--warning-bg);color:var(--warning)}'
    '.metrics{display:flex;gap:.6rem;flex-wrap:wrap}'
    '.metric{background:var(--surface);border-radius:8px;padding:.5rem .8rem;'
    'min-width:88px}.metric .k{font-size:12px;color:var(--muted)}'
    '.metric .v{font-size:20px;font-weight:600}'
    '.chip{font-family:ui-monospace,monospace;font-size:12px;padding:2px 7px;'
    'border-radius:6px;background:var(--surface);border:1px solid var(--border)}'
    '.flow{display:flex;align-items:center;gap:6px;flex-wrap:wrap;'
    'padding:8px 12px;border:1px solid var(--border);border-radius:8px;'
    'margin:6px 0}'
    '.flow.bad{border-color:var(--danger);border-left:3px solid var(--danger);'
    'background:var(--danger-bg)}.flow .sep{color:var(--muted)}'
    '.flow .status{margin-left:auto;font-size:12px;color:var(--muted)}'
    '.chip.bad{background:var(--danger-bg);border-color:var(--danger);'
    'color:var(--danger)}'
    'section.card{border:1px solid var(--border);border-radius:12px;'
    'padding:1rem 1.2rem;margin:1rem 0}'
    'ol.str{list-style:none;padding:0;margin:.4rem 0}'
    'ol.str li{position:relative;padding:0 0 14px 30px}'
    'ol.str li:before{content:"";position:absolute;left:10px;top:22px;'
    'bottom:-2px;width:2px;background:var(--border)}'
    'ol.str li:last-child{padding-bottom:0}'
    'ol.str li:last-child:before{display:none}'
    'ol.str .num{position:absolute;left:0;top:0;width:22px;height:22px;'
    'border-radius:50%;background:var(--surface);color:var(--muted);'
    'display:inline-flex;align-items:center;justify-content:center;'
    'font-size:12px}'
    'ol.str li.fail .num{background:var(--danger-bg);color:var(--danger)}'
    'ol.str .act{color:var(--muted);font-size:13px}'
    'ol.str li.fail .act{color:var(--danger)}'
    '.shots{display:flex;gap:10px;flex-wrap:wrap;margin:.6rem 0}'
    'figure.evidence{flex:1;min-width:140px;margin:0}'
    'figure.evidence img{width:100%;border:1px solid var(--border);'
    'border-radius:8px;display:block}'
    'figure.evidence figcaption{font-size:12px;color:var(--muted);'
    'margin-top:4px}'
    '.tabs{display:flex;flex-wrap:wrap;gap:8px}.tabs input{display:none}'
    '.tabs label{order:1;font-size:13px;padding:6px 12px;'
    'border:1px solid var(--border);border-radius:8px;cursor:pointer;'
    'color:var(--muted)}'
    '.tabs input:checked+label{background:var(--info-bg);color:var(--info);'
    'border-color:var(--info)}'
    '.tabs .panel{order:2;width:100%;display:none;margin-top:12px}'
    '.tabs input:checked+label+.panel{display:block}'
    'table{border-collapse:collapse;width:100%;font-size:13px;margin:.4rem 0}'
    'th,td{border:1px solid var(--border);padding:.35rem .6rem;text-align:left}'
    '.tier-ok{color:var(--success)}.tier-bad{color:var(--danger)}'
    '.tier-skip{color:var(--muted)}.note{color:var(--muted);font-size:13px}'
    '.verdict{border-radius:8px;padding:.5rem .7rem;margin:.6rem 0;'
    'font-size:14px}.verdict.bug{background:var(--danger-bg)}'
    '.verdict.intended{background:var(--warning-bg)}'
    '.verdict.flake{background:var(--surface)}'
    'section.pending{border:1px solid var(--warning);border-radius:12px;'
    'padding:1rem 1.2rem;margin:1rem 0;background:var(--warning-bg)}'
    'section.cluster{border:1px solid var(--info);border-radius:12px;'
    'padding:1rem 1.2rem;margin:1rem 0;background:var(--info-bg)}'
    '$graphSvgRules';
