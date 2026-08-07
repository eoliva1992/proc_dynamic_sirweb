import 'package:flutter_monaco/flutter_monaco.dart';

/// A single PL/SQL syntax issue found by the manual checker.
class PlSqlIssue {
  final int line; // 1-based
  final int col; // 1-based
  final int endCol; // 1-based, exclusive
  final String message;
  final MarkerSeverity severity;

  const PlSqlIssue({
    required this.line,
    required this.col,
    required this.endCol,
    required this.message,
    this.severity = MarkerSeverity.error,
  });
}

/// Basic structural PL/SQL checker used as fallback when the ANTLR bundle
/// (assets/plsql_checker.js) is not yet available.
///
/// Detects:
/// - Unterminated string literals (unclosed `'`)
/// - Unclosed block comments (`/* ... */`)
/// - BEGIN/END imbalance
List<PlSqlIssue> checkPlSqlSyntax(String code) {
  final issues = <PlSqlIssue>[];
  final lines = code.split('\n');

  // ── Pass 1: tokenise to find unterminated strings and block comments ─────
  bool inBlock = false; // inside /* ... */
  bool inStr = false; // inside '...'
  int strStartLine = 0;
  int strStartCol = 0;
  int blockStartLine = 0;
  int blockStartCol = 0;

  for (int li = 0; li < lines.length; li++) {
    final lineNo = li + 1;
    final ln = lines[li];
    int ci = 0;

    while (ci < ln.length) {
      if (inBlock) {
        if (ci + 1 < ln.length && ln[ci] == '*' && ln[ci + 1] == '/') {
          inBlock = false;
          ci += 2;
        } else {
          ci++;
        }
      } else if (inStr) {
        if (ln[ci] == "'") {
          // doubled quote is an escaped quote, not a close
          if (ci + 1 < ln.length && ln[ci + 1] == "'") {
            ci += 2;
          } else {
            inStr = false;
            ci++;
          }
        } else {
          ci++;
        }
        // Single-quoted strings don't span lines in standard PL/SQL
        if (ci >= ln.length && inStr) {
          issues.add(
            PlSqlIssue(
              line: strStartLine,
              col: strStartCol,
              endCol: strStartCol + 1,
              message: "Cadena de texto sin cerrar (comilla simple no cerrada)",
            ),
          );
          inStr = false; // recover so we continue parsing
        }
      } else {
        // Normal context
        if (ci + 1 < ln.length && ln[ci] == '/' && ln[ci + 1] == '*') {
          inBlock = true;
          blockStartLine = lineNo;
          blockStartCol = ci + 1;
          ci += 2;
        } else if (ci + 1 < ln.length && ln[ci] == '-' && ln[ci + 1] == '-') {
          break; // rest of line is a line comment
        } else if (ln[ci] == "'") {
          inStr = true;
          strStartLine = lineNo;
          strStartCol = ci + 1;
          ci++;
        } else {
          ci++;
        }
      }
    }
  }

  if (inBlock) {
    issues.add(
      PlSqlIssue(
        line: blockStartLine,
        col: blockStartCol,
        endCol: blockStartCol + 2,
        message: "Comentario de bloque sin cerrar (falta */)",
      ),
    );
  }

  // ── Pass 2: BEGIN/END balance (keywords only, outside strings/comments) ──
  final beginRe = RegExp(r'\bBEGIN\b', caseSensitive: false);
  // Only match END that closes a BEGIN block — not END IF / END LOOP / END CASE
  final endRe = RegExp(r'\bEND\b(?!\s*(IF|LOOP|CASE)\b)', caseSensitive: false);

  // Strip strings and comments to avoid false positives
  final stripped = _stripCommentsAndStrings(code);
  final strippedLines = stripped.split('\n');

  // PACKAGE and TYPE use AS/IS...END without BEGIN — balance check is invalid for them
  final isPackageOrType = RegExp(
    r'^\s*(?:CREATE\s+(?:OR\s+REPLACE\s+)?)?(?:PACKAGE|TYPE)\b',
    caseSensitive: false,
  ).hasMatch(stripped);

  if (!isPackageOrType) {
    int depth = 0;
    int firstExtraEndLine = -1;
    int firstExtraEndCol = 1;

    for (int li = 0; li < strippedLines.length; li++) {
      final lineNo = li + 1;
      final ln = strippedLines[li];

      // Count BEGINs
      depth += beginRe.allMatches(ln).length;

      // Count ENDs — each END closes one BEGIN
      for (final m in endRe.allMatches(ln)) {
        depth--;
        if (depth < 0 && firstExtraEndLine == -1) {
          firstExtraEndLine = lineNo;
          firstExtraEndCol = m.start + 1;
        }
      }
    }

    if (firstExtraEndLine != -1) {
      issues.add(
        PlSqlIssue(
          line: firstExtraEndLine,
          col: firstExtraEndCol,
          endCol: firstExtraEndCol + 3,
          message: "END sin BEGIN correspondiente",
        ),
      );
    } else if (depth > 0) {
      // Find the line of the last unclosed BEGIN
      int remaining = depth;
      int beginErrLine = strippedLines.length;
      int beginErrCol = 1;
      for (int li = strippedLines.length - 1; li >= 0 && remaining > 0; li--) {
        final ln = strippedLines[li];
        final matches = beginRe.allMatches(ln).toList();
        for (int mi = matches.length - 1; mi >= 0 && remaining > 0; mi--) {
          remaining--;
          if (remaining == 0) {
            beginErrLine = li + 1;
            beginErrCol = matches[mi].start + 1;
          }
        }
      }
      issues.add(
        PlSqlIssue(
          line: beginErrLine,
          col: beginErrCol,
          endCol: beginErrCol + 5,
          message:
              "BEGIN sin END correspondiente ($depth bloque${depth == 1 ? '' : 's'} sin cerrar)",
        ),
      );
    }
  } // end if (!isPackageOrType)

  return issues;
}

/// Replaces string literals and comments with spaces (preserving line counts).
String _stripCommentsAndStrings(String code) {
  final buf = StringBuffer();
  int i = 0;
  while (i < code.length) {
    if (i + 1 < code.length && code[i] == '/' && code[i + 1] == '*') {
      // Block comment — replace content with spaces until */
      buf.write('  ');
      i += 2;
      while (i < code.length) {
        if (i + 1 < code.length && code[i] == '*' && code[i + 1] == '/') {
          buf.write('  ');
          i += 2;
          break;
        }
        buf.write(code[i] == '\n' ? '\n' : ' ');
        i++;
      }
    } else if (i + 1 < code.length && code[i] == '-' && code[i + 1] == '-') {
      // Line comment — replace until newline
      while (i < code.length && code[i] != '\n') {
        buf.write(' ');
        i++;
      }
    } else if (code[i] == "'") {
      // String literal
      buf.write(' ');
      i++;
      while (i < code.length) {
        if (code[i] == "'") {
          buf.write(' ');
          i++;
          if (i < code.length && code[i] == "'") {
            // doubled quote
            buf.write(' ');
            i++;
          } else {
            break;
          }
        } else {
          buf.write(code[i] == '\n' ? '\n' : ' ');
          i++;
        }
      }
    } else {
      buf.write(code[i]);
      i++;
    }
  }
  return buf.toString();
}
