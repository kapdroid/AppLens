import 'dart:convert';
import 'dart:io';

import 'provider.dart';
import 'schema.dart';

/// The Phase-1, zero-key adapter (ARCHITECTURE.md §12): a human is the
/// transport. [complete] writes the evidence package (and any diff images) to
/// disk, prints paste-into-a-chat-UI instructions, then polls until the
/// operator drops a verdict JSON at [verdictPath], which it validates against
/// the request's schema. It implements the same port as any model adapter — so
/// the day `ClaudeProvider` is wired in, nothing above the port changes, and
/// every manual verdict collected is eval data for the automated providers.
///
/// [verdictPath] must be empty when [complete] is called (the caller uses a
/// fresh path per request); a stale file would be read as this run's answer.
class ManualProvider implements LlmProvider {
  ManualProvider({
    required this.evidencePath,
    required this.verdictPath,
    StringSink? out,
    this.pollInterval = const Duration(seconds: 1),
    this.timeout = const Duration(minutes: 30),
  }) : _out = out ?? stdout;

  /// Where the human-readable evidence markdown is written.
  final String evidencePath;

  /// Where the operator saves the JSON verdict; [complete] waits for it.
  final String verdictPath;

  final StringSink _out;
  final Duration pollInterval;
  final Duration timeout;

  @override
  LlmCapabilities get capabilities => const LlmCapabilities(
        vision: true, // a human can see the attached diff images
        jsonMode: false, // the operator hand-writes the JSON
        maxContextTokens: 1 << 30,
      );

  @override
  Future<LlmResult> complete(LlmRequest request) async {
    final evidence = File(evidencePath)..parent.createSync(recursive: true);
    _writeImages(request, evidence.parent);
    evidence.writeAsStringSync(_renderEvidence(request));
    _out
      ..writeln('AppLens manual triage — a human is the LLM this run:')
      ..writeln(
          '  1. Open  $evidencePath  and paste it (with images) into a chat UI.')
      ..writeln('  2. Save the JSON answer to  $verdictPath');

    final clock = Stopwatch()..start();
    while (true) {
      final file = File(verdictPath);
      if (file.existsSync()) {
        return _readVerdict(file, request);
      }
      if (clock.elapsed >= timeout) {
        throw LlmException(
          'no verdict at $verdictPath after ${timeout.inSeconds}s',
        );
      }
      await Future<void>.delayed(pollInterval);
    }
  }

  LlmResult _readVerdict(File file, LlmRequest request) {
    final Object? decoded;
    try {
      decoded = jsonDecode(file.readAsStringSync());
    } on FormatException catch (e) {
      throw LlmException(
          'verdict at $verdictPath is not valid JSON: ${e.message}');
    }
    if (decoded is! Map) {
      throw LlmException('verdict at $verdictPath must be a JSON object');
    }
    final json = decoded.cast<String, Object?>();
    final errors = validateAgainstSchema(json, request.jsonSchema);
    if (errors.isNotEmpty) {
      throw LlmException(
        'verdict at $verdictPath failed schema: ${errors.join('; ')}',
      );
    }
    return LlmResult(json: json);
  }

  void _writeImages(LlmRequest request, Directory dir) {
    final images = [for (final m in request.messages) ...m.images];
    for (var i = 0; i < images.length; i++) {
      File('${dir.path}/image_$i.png').writeAsBytesSync(images[i].bytes);
    }
  }

  String _renderEvidence(LlmRequest request) {
    final out = StringBuffer('# AppLens triage — paste into your chat UI\n\n');
    var imageIndex = 0;
    for (final message in request.messages) {
      out.writeln('## ${message.role.name}\n\n${message.text}\n');
      for (var i = 0; i < message.images.length; i++) {
        out.writeln('- image: `image_${imageIndex++}.png` (in this folder)');
      }
      if (message.images.isNotEmpty) {
        out.writeln();
      }
    }
    out
      ..writeln('## Answer with JSON matching this schema\n')
      ..writeln('```json')
      ..writeln(const JsonEncoder.withIndent('  ').convert(request.jsonSchema))
      ..writeln('```\n')
      ..writeln('Save your answer to `$verdictPath`.');
    return out.toString();
  }
}
