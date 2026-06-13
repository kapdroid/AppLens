import 'dart:math' as math;

import 'package:applens_core/applens_core.dart';

/// Renders the given [nodeIds] of [graph] as an inline SVG: each node a labelled
/// box, each intra-set edge a line. [failedIds] are filled red and [focusId]
/// gets a heavier outline. Layout is a naive grid — readable for the
/// module-sized subgraphs humans actually review (ARCHITECTURE.md §5); a richer
/// layout can replace it without changing callers.
String renderGraphSvg(
  Graph graph,
  Iterable<String> nodeIds, {
  String? focusId,
  Set<String> failedIds = const {},
}) {
  final ids = nodeIds.where(graph.byId.containsKey).toList()..sort();
  if (ids.isEmpty) {
    return '<svg xmlns="http://www.w3.org/2000/svg" width="0" height="0"></svg>';
  }

  const cellW = 180.0;
  const cellH = 90.0;
  const boxW = 156.0;
  const boxH = 50.0;
  final cols = math.sqrt(ids.length).ceil();
  final rows = (ids.length / cols).ceil();

  final topLeft = <String, ({double x, double y})>{};
  for (var i = 0; i < ids.length; i++) {
    topLeft[ids[i]] = (x: 20 + (i % cols) * cellW, y: 20 + (i ~/ cols) * cellH);
  }
  ({double x, double y}) center(String id) =>
      (x: topLeft[id]!.x + boxW / 2, y: topLeft[id]!.y + boxH / 2);

  final edges = StringBuffer();
  for (final id in ids) {
    for (final edge in graph.byId[id]!.payload.edges) {
      if (!topLeft.containsKey(edge.target)) {
        continue;
      }
      final from = center(id);
      final to = center(edge.target);
      edges.write(
        '<line x1="${from.x}" y1="${from.y}" x2="${to.x}" y2="${to.y}" '
        'stroke="#999" stroke-width="1"/>',
      );
    }
  }

  final boxes = StringBuffer();
  for (final id in ids) {
    final p = topLeft[id]!;
    final fill = failedIds.contains(id) ? '#f8d7da' : '#e7f1ff';
    final stroke = id == focusId ? '#b00020' : '#5b8def';
    final strokeWidth = id == focusId ? 3 : 1;
    boxes.write(
      '<rect x="${p.x}" y="${p.y}" width="$boxW" height="$boxH" rx="6" '
      'fill="$fill" stroke="$stroke" stroke-width="$strokeWidth"/>'
      '<text x="${p.x + boxW / 2}" y="${p.y + boxH / 2 + 4}" '
      'text-anchor="middle" font-family="monospace" font-size="11">'
      '${escapeXml(id)}</text>',
    );
  }

  final width = 40 + cols * cellW;
  final height = 40 + rows * cellH;
  return '<svg xmlns="http://www.w3.org/2000/svg" width="$width" '
      'height="$height" viewBox="0 0 $width $height">$edges$boxes</svg>';
}

/// Renders a whole module's subgraph (`<module>.*` nodes). Backs `graph show`.
String renderModule(Graph graph, String module) => renderGraphSvg(
      graph,
      graph.nodes.map((n) => n.id).where((id) => id.startsWith('$module.')),
    );

/// Renders [focusId] with its immediate inbound and outbound neighbours, the
/// focus node highlighted — the self-locating subgraph shown next to a failure.
String renderNeighborhood(
  Graph graph,
  String focusId, {
  Set<String> failedIds = const {},
}) {
  final ids = <String>{focusId};
  final focus = graph.byId[focusId];
  if (focus != null) {
    for (final edge in focus.payload.edges) {
      ids.add(edge.target);
    }
  }
  for (final node in graph.nodes) {
    if (node.payload.edges.any((e) => e.target == focusId)) {
      ids.add(node.id);
    }
  }
  return renderGraphSvg(graph, ids, focusId: focusId, failedIds: failedIds);
}

/// Minimal XML escaping for text embedded in SVG/HTML.
String escapeXml(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');
