import 'package:applens_core/applens_core.dart';

import 'fingerprint.dart';

/// Whether [identity] matches an observed [fingerprint]: compatible route, same
/// overlay, all required anchors present, and every flag constraint accepted by
/// the observed value.
bool identityMatches(NodeIdentity identity, Fingerprint fingerprint) {
  if (identity.route != null && identity.route != fingerprint.route) {
    return false;
  }
  if (identity.overlay != fingerprint.overlay) {
    return false;
  }
  for (final anchor in identity.anchors) {
    if (!fingerprint.anchors.contains(anchor)) {
      return false;
    }
  }
  for (final entry in identity.flags.entries) {
    final observed = fingerprint.flags[entry.key];
    if (observed == null || !entry.value.accepts(observed)) {
      return false;
    }
  }
  return true;
}

/// The id of the node [fingerprint] matches, or null if none. Nodes are
/// considered in sorted id order for determinism; a validated graph (no
/// fingerprint ambiguity) guarantees at most one match.
String? matchNode(Fingerprint fingerprint, Graph graph) {
  final ids = graph.byId.keys.toList()..sort();
  for (final id in ids) {
    if (identityMatches(graph.byId[id]!.identity, fingerprint)) {
      return id;
    }
  }
  return null;
}
