import 'package:applens_cli/applens_cli.dart';
import 'package:test/test.dart';

void main() {
  test('CLI exposes a version', () {
    expect(applensCliVersion, isNotEmpty);
  });
}
