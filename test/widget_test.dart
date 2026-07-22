import 'package:flutter_test/flutter_test.dart';
import 'package:getai_chat/widgets/message_bubble.dart';

void main() {
  test('converts legacy formula-only code fences to display LaTeX', () {
    const markdown = '''Rumus LCG:

```
X_{n+1} = (a \\times X_n + c) \\mod m
```
''';

    final normalized = normalizeMathMarkdown(markdown);

    expect(
      normalized,
      contains(
        r'$$'
        '\n'
        r'X_{n+1} = (a \times X_n + c) \mod m'
        '\n'
        r'$$',
      ),
    );
    expect(normalized, isNot(contains('```')));
  });
}
