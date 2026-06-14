import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:applens_llm/applens_llm.dart';
import 'package:test/test.dart';

const _schema = <String, Object?>{
  'type': 'object',
  'required': ['verdict', 'reasoning'],
  'properties': {
    'verdict': {
      'type': 'string',
      'enum': ['bug', 'intended', 'flake'],
    },
    'reasoning': {'type': 'string'},
  },
};

LlmRequest _request() => const LlmRequest(
      messages: [LlmMessage(LlmRole.user, 'Why did shop.dashboard drift?')],
      jsonSchema: _schema,
    );

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('applens_manual'));
  tearDown(() => dir.deleteSync(recursive: true));

  ManualProvider provider({Duration timeout = const Duration(minutes: 30)}) =>
      ManualProvider(
        evidencePath: '${dir.path}/evidence.md',
        verdictPath: '${dir.path}/verdict.json',
        out: StringBuffer(),
        timeout: timeout,
      );

  test('reads and schema-validates the verdict the operator drops in',
      () async {
    File('${dir.path}/verdict.json').writeAsStringSync(
      jsonEncode({'verdict': 'intended', 'reasoning': 'matches restyle PR'}),
    );

    final result = await provider().complete(_request());

    expect(result.json['verdict'], 'intended');
    expect(File('${dir.path}/evidence.md').existsSync(), isTrue);
  });

  test('writes evidence markdown and any images for pasting', () async {
    File('${dir.path}/verdict.json')
        .writeAsStringSync(jsonEncode({'verdict': 'bug', 'reasoning': 'x'}));
    final out = StringBuffer();

    await ManualProvider(
      evidencePath: '${dir.path}/evidence.md',
      verdictPath: '${dir.path}/verdict.json',
      out: out,
    ).complete(
      LlmRequest(
        messages: [
          LlmMessage(
            LlmRole.user,
            'see the diff',
            images: [
              LlmImage(bytes: Uint8List.fromList([1, 2, 3]))
            ],
          ),
        ],
        jsonSchema: _schema,
      ),
    );

    final md = File('${dir.path}/evidence.md').readAsStringSync();
    expect(md, contains('paste into your chat UI'));
    expect(md, contains('image_0.png'));
    expect(File('${dir.path}/image_0.png').existsSync(), isTrue);
    expect(out.toString(), contains('manual triage'));
  });

  test('rejects a verdict that violates the schema', () {
    File('${dir.path}/verdict.json')
        .writeAsStringSync(jsonEncode({'verdict': 'nope'}));
    expect(provider().complete(_request()), throwsA(isA<LlmException>()));
  });

  test('rejects non-JSON garbage', () {
    File('${dir.path}/verdict.json').writeAsStringSync('not json');
    expect(provider().complete(_request()), throwsA(isA<LlmException>()));
  });

  test('times out when no verdict ever appears', () {
    expect(
      provider(timeout: Duration.zero).complete(_request()),
      throwsA(isA<LlmException>()),
    );
  });
}
