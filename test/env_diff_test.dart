import 'package:flutter_test/flutter_test.dart';

// Test targets pure logic functions: normalization and diff hunk computation
String normalizeEol(String text) =>
    text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

typedef Hunk = ({int origStart, int origEnd, int modStart, int modEnd});

List<Hunk> computeHunks(String orig, String mod) {
  final cleanOrig = normalizeEol(orig);
  final cleanMod = normalizeEol(mod);
  final a = cleanOrig.split('\n');
  final b = cleanMod.split('\n');
  final n = a.length;
  final m = b.length;
  final dp = List.generate(n + 1, (_) => List.filled(m + 1, 0));
  for (var i = n - 1; i >= 0; i--) {
    for (var j = m - 1; j >= 0; j--) {
      dp[i][j] = a[i] == b[j]
          ? dp[i + 1][j + 1] + 1
          : (dp[i + 1][j] >= dp[i][j + 1] ? dp[i + 1][j] : dp[i][j + 1]);
    }
  }
  final matches = <(int, int)>[];
  var i = 0, j = 0;
  while (i < n && j < m) {
    if (a[i] == b[j]) {
      matches.add((i, j));
      i++;
      j++;
    } else if (dp[i + 1][j] >= dp[i][j + 1]) {
      i++;
    } else {
      j++;
    }
  }
  final hunks = <Hunk>[];
  var po = -1, pm = -1;
  for (final (mi, mj) in [...matches, (n, m)]) {
    if (mi > po + 1 || mj > pm + 1) {
      hunks.add((origStart: po + 1, origEnd: mi, modStart: pm + 1, modEnd: mj));
    }
    po = mi;
    pm = mj;
  }
  return hunks;
}

void main() {
  group('EnvDiff - EOL Normalization & Hunk Computation', () {
    test('normalizeEol converts CRLF and CR to LF', () {
      const windows = 'BEGIN\r\n  NULL;\r\nEND;';
      const macClassic = 'BEGIN\r  NULL;\rEND;';
      const unix = 'BEGIN\n  NULL;\nEND;';

      expect(normalizeEol(windows), unix);
      expect(normalizeEol(macClassic), unix);
      expect(normalizeEol(unix), unix);
    });

    test('identical content with different line endings produces 0 hunks', () {
      const origCrlf =
          'CREATE OR REPLACE PROCEDURE PR_TEST IS\r\nBEGIN\r\n  NULL;\r\nEND;';
      const modLf =
          'CREATE OR REPLACE PROCEDURE PR_TEST IS\nBEGIN\n  NULL;\nEND;';

      final hunks = computeHunks(origCrlf, modLf);
      expect(hunks, isEmpty);
    });

    test('detects single line modification across environments', () {
      const orig = 'BEGIN\n  DBMS_OUTPUT.PUT_LINE(1);\nEND;';
      const mod = 'BEGIN\r\n  DBMS_OUTPUT.PUT_LINE(2);\r\nEND;';

      final hunks = computeHunks(orig, mod);
      expect(hunks.length, 1);
      expect(hunks.first.origStart, 1);
      expect(hunks.first.origEnd, 2);
      expect(hunks.first.modStart, 1);
      expect(hunks.first.modEnd, 2);
    });

    test('detects added and removed lines accurately', () {
      const orig = 'PROCEDURE P IS\nBEGIN\n  NULL;\nEND;';
      const mod =
          'PROCEDURE P IS\nBEGIN\n  DBMS_OUTPUT.PUT_LINE(\'START\');\n  NULL;\n  DBMS_OUTPUT.PUT_LINE(\'END\');\nEND;';

      final hunks = computeHunks(orig, mod);
      expect(hunks.length, 2);
    });
  });
}
